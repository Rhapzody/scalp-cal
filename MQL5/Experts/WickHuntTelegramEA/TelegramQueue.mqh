#ifndef WICK_HUNT_TELEGRAM_QUEUE
#define WICK_HUNT_TELEGRAM_QUEUE
#include "../../Indicators/WickHuntSRFlow/WickHuntContextCore.mqh"

bool WHTSafeName(const string value)
{
   if(StringLen(value)<1 || StringLen(value)>48) return false;
   for(int i=0;i<StringLen(value);i++)
   {
      ushort c=StringGetCharacter(value,i);
      if(!((c>='a' && c<='z') || (c>='A' && c<='Z') || (c>='0' && c<='9') || c=='_' || c=='-')) return false;
   }
   return true;
}
string WHTHash(const string value)
{
   uchar data[],key[],digest[];
   int n=StringToCharArray(value,data,0,WHOLE_ARRAY,CP_UTF8)-1;
   if(n<0 || ArrayResize(data,n)!=n || CryptEncode(CRYPT_HASH_SHA256,data,key,digest)!=32) return "";
   string out="";
   for(int i=0;i<16;i++) out+=StringFormat("%02x",(int)digest[i]);
   return out;
}
string WHTAccountKey()
{
   return WHTHash(AccountInfoString(ACCOUNT_SERVER)+"|"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)));
}
string WHTFolder(const string channel)
{
   string account=WHTAccountKey();
   if(account=="" || !WHTSafeName(channel)) return "";
   string base="WickHuntTelegram", scoped=base+"\\"+account;
   FolderCreate(base); FolderCreate(scoped); FolderCreate(scoped+"\\"+channel);
   return scoped+"\\"+channel;
}
string WHTEventID(const string instance,const long setup,const int direction)
{
   return instance+"_"+IntegerToString(setup)+"_"+(direction==1 ? "B" : "S");
}
bool WHTExists(const string folder,const string id)
{
   return FileIsExist(folder+"\\"+id+".pending") || FileIsExist(folder+"\\"+id+".sent") ||
          FileIsExist(folder+"\\"+id+".failed");
}
string WHTJson(const string value)
{
   string out="\"";
   for(int i=0;i<StringLen(value);i++)
   {
      ushort c=StringGetCharacter(value,i);
      if(c=='"') out+="\\\"";
      else if(c=='\\') out+="\\\\";
      else if(c=='\n') out+="\\n";
      else if(c=='\r') out+="\\r";
      else if(c=='\t') out+="\\t";
      else if(c<32) out+=StringFormat("\\u%04x",(int)c);
      else out+=ShortToString(c);
   }
   return out+"\"";
}
void WHTWriteSignal(const int f,const WSSignal &e)
{
   FileWriteLong(f,e.time); FileWriteLong(f,e.setup_time); FileWriteLong(f,e.break_time); FileWriteLong(f,e.pivot_time);
   FileWriteDouble(f,e.price); FileWriteDouble(f,e.sr);
   FileWriteInteger(f,e.direction); FileWriteInteger(f,e.sr_type); FileWriteInteger(f,e.pattern);
   FileWriteDouble(f,e.context_sr); FileWriteLong(f,e.anchor_time); FileWriteLong(f,e.trend_pivot);
   FileWriteLong(f,e.hold_time); FileWriteInteger(f,e.retest_bar);
}
void WHTReadSignal(const int f,WSSignal &e)
{
   e.time=FileReadLong(f); e.setup_time=FileReadLong(f); e.break_time=FileReadLong(f); e.pivot_time=FileReadLong(f);
   e.price=FileReadDouble(f); e.sr=FileReadDouble(f);
   e.direction=FileReadInteger(f); e.sr_type=FileReadInteger(f); e.pattern=FileReadInteger(f);
   e.context_sr=FileReadDouble(f); e.anchor_time=FileReadLong(f); e.trend_pivot=FileReadLong(f);
   e.hold_time=FileReadLong(f); e.retest_bar=FileReadInteger(f);
}
bool WHTSignalValid(const WSSignal &e)
{
   return e.time>=e.setup_time && e.setup_time>0 && e.break_time>=e.setup_time && e.pivot_time>0 &&
          MathIsValidNumber(e.price) && e.price>0 && MathIsValidNumber(e.sr) && e.sr>0 &&
          (e.direction==1 || e.direction==-1) && (e.sr_type==1 || e.sr_type==-1) &&
          e.pattern>=0 && e.pattern<=3 && MathIsValidNumber(e.context_sr) && e.retest_bar>=0;
}
// Publish only a fully written, flushed file. The sender ignores .tmp files.
bool WHTPublish(const string folder,const string id,const WSSignal &e,const string message)
{
   if(WHTExists(folder,id)) return true;
   uchar text[];
   int n=StringToCharArray(message,text,0,WHOLE_ARRAY,CP_UTF8)-1;
   if(n<1 || n>16384 || ArrayResize(text,n)!=n || !WHTSignalValid(e)) return false;
   string temp=folder+"\\"+id+".tmp", target=folder+"\\"+id+".pending";
   int f=FileOpen(temp,FILE_WRITE|FILE_BIN);
   if(f==INVALID_HANDLE) return false;
   ResetLastError();
   FileWriteInteger(f,0x57485431); FileWriteInteger(f,1); FileWriteLong(f,(long)TimeLocal());
   WHTWriteSignal(f,e); FileWriteInteger(f,n);
   uint written=FileWriteArray(f,text,0,n);
   bool ok=written==(uint)n && FileTell(f)==(ulong)(116+n) && GetLastError()==0;
   FileFlush(f); ok=ok && GetLastError()==0;
   FileClose(f);
   return ok && FileMove(temp,0,target,0);
}
bool WHTRead(const string path,WSSignal &e,string &message,long &queued)
{
   int f=FileOpen(path,FILE_READ|FILE_BIN|FILE_SHARE_READ);
   if(f==INVALID_HANDLE) return false;
   ResetLastError();
   bool ok=FileSize(f)>=117 && FileSize(f)<=16500;
   int magic=FileReadInteger(f),schema=FileReadInteger(f);
   queued=FileReadLong(f); WHTReadSignal(f,e);
   int n=FileReadInteger(f);
   uchar text[];
   ok=ok && magic==0x57485431 && schema==1 && queued>0 && WHTSignalValid(e) &&
      n>=1 && n<=16384 && FileSize(f)==(ulong)(116+n);
   if(ok) ok=FileReadArray(f,text,0,n)==(uint)n && GetLastError()==0;
   if(ok) message=CharArrayToString(text,0,n,CP_UTF8);
   FileClose(f);
   return ok && StringLen(message)>0;
}
// A tiny top-level JSON boolean reader: quoted values and nested objects cannot
// masquerade as Telegram's actual top-level ok=true acknowledgement.
bool WHTJsonOK(const string json)
{
   int depth=0;
   for(int i=0;i<StringLen(json);i++)
   {
      ushort c=StringGetCharacter(json,i);
      if(c=='{' || c=='[') { depth++; continue; }
      if(c=='}' || c==']') { depth--; continue; }
      if(c!='"') continue;
      int start=++i;
      bool escaped=false;
      for(;i<StringLen(json);i++)
      {
         c=StringGetCharacter(json,i);
         if(escaped) { escaped=false; continue; }
         if(c=='\\') { escaped=true; continue; }
         if(c=='"') break;
      }
      if(depth!=1 || StringSubstr(json,start,i-start)!="ok") continue;
      int j=i+1;
      while(j<StringLen(json) && StringGetCharacter(json,j)<=32) j++;
      if(j>=StringLen(json) || StringGetCharacter(json,j)!=':') continue;
      j++;
      while(j<StringLen(json) && StringGetCharacter(json,j)<=32) j++;
      if(StringSubstr(json,j,4)!="true") return false;
      j+=4;
      while(j<StringLen(json) && StringGetCharacter(json,j)<=32) j++;
      return j<StringLen(json) && (StringGetCharacter(json,j)==',' || StringGetCharacter(json,j)=='}');
   }
   return false;
}
int WHTRetryAfter(const string json)
{
   int at=StringFind(json,"\"retry_after\"");
   if(at<0) return 0;
   at=StringFind(json,":",at);
   if(at<0) return 0;
   at++;
   while(at<StringLen(json) && StringGetCharacter(json,at)<=32) at++;
   long seconds=StringToInteger(StringSubstr(json,at));
   return (int)MathMax(0,MathMin(86400,seconds));
}
#endif
