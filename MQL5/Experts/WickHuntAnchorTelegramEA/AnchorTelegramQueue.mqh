#ifndef WHA_TELEGRAM_QUEUE
#define WHA_TELEGRAM_QUEUE
// Keep the failing operation/error before FileClose or other API calls change it.
// No tokens or chat IDs enter this diagnostic. Repeated failures are throttled.
string g_wat_file_operation="",g_wat_file_path="",g_wat_file_log_key="";
int g_wat_file_error=0;
ulong g_wat_file_logged_at=0;
void WATClearFileError()
{ g_wat_file_operation=""; g_wat_file_path=""; g_wat_file_error=0; }
bool WATFileError(const string operation,const string path,const int error)
{
   g_wat_file_operation=operation; g_wat_file_path=path; g_wat_file_error=error;
   string key=operation+"|"+path+"|"+(string)error;
   ulong now=GetTickCount64();
   if(key!=g_wat_file_log_key || now-g_wat_file_logged_at>=30000)
   {
      Print("WickHuntAnchor I/O | operation=",operation," | error=",error,
            " | file=",path," | data=",TerminalInfoString(TERMINAL_DATA_PATH));
      g_wat_file_log_key=key; g_wat_file_logged_at=now;
   }
   return false;
}
string WATFileErrorText()
{
   return g_wat_file_operation=="" ? "see Experts log" :
          g_wat_file_operation+" error "+(string)g_wat_file_error;
}
bool WATMoveFile(const string source,const string destination,const int flags)
{
   ResetLastError();
   if(FileMove(source,0,destination,flags)) return true;
   return WATFileError("move",source+" -> "+destination,GetLastError());
}
bool WATSafeName(const string value)
{
   if(StringLen(value)<1 || StringLen(value)>48) return false;
   for(int i=0;i<StringLen(value);i++)
   {
      ushort c=StringGetCharacter(value,i);
      if(!((c>='a' && c<='z') || (c>='A' && c<='Z') || (c>='0' && c<='9') || c=='_' || c=='-')) return false;
   }
   return true;
}
string WATHash(const string value)
{
   uchar data[],key[],digest[];
   int n=StringToCharArray(value,data,0,WHOLE_ARRAY,CP_UTF8)-1;
   if(n<0 || ArrayResize(data,n)!=n || CryptEncode(CRYPT_HASH_SHA256,data,key,digest)!=32) return "";
   string out="";
   for(int i=0;i<16;i++) out+=StringFormat("%02x",(int)digest[i]);
   return out;
}
string WATAccountKey()
{
   return StringSubstr(WATHash(AccountInfoString(ACCOUNT_SERVER)+"|"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))),0,16);
}
string WATFolder(const string channel)
{
   string account=WATAccountKey();
   if(account=="" || !WATSafeName(channel)) return "";
   string base="WHAtelegram", scoped=base+"\\"+account;
   FolderCreate(base); FolderCreate(scoped); FolderCreate(scoped+"\\"+channel);
   return scoped+"\\"+channel;
}
string WATEventID(const string instance,const long setup,const int direction)
{
   return instance+"_"+IntegerToString(setup)+"_"+(direction==1 ? "B" : "S");
}
bool WATExists(const string folder,const string id)
{
   return FileIsExist(folder+"\\"+id+".pending") || FileIsExist(folder+"\\"+id+".sent") ||
          FileIsExist(folder+"\\"+id+".failed");
}
string WATJson(const string value)
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

struct WATRecord
{
   long queued,time,setup,anchor;
   double price,tip,head;
   int direction,pattern,observation,kind;
   string instance,message,main_photo,lower_photo,parent;
};
bool WATWriteString(const int f,const string value)
{
   // Optional fields can be NULL after a zero-initialized record, or empty
   // after reading an existing record. Never pass either to StringToCharArray:
   // a deinitialized string can set ERR_NOTINITIALIZED_STRING (4009).
   // Schema 1 already represents an absent string with a 4-byte zero length.
   if(value==NULL || value=="") return FileWriteInteger(f,0)==4;
   uchar bytes[];
   int n=StringToCharArray(value,bytes,0,WHOLE_ARRAY,CP_UTF8)-1;
   if(n<0 || n>16384 || ArrayResize(bytes,n)!=n) return false;
   if(FileWriteInteger(f,n)!=4) return false;
   return n==0 || FileWriteArray(f,bytes,0,n)==(uint)n;
}
bool WATReadString(const int f,string &value)
{
   int n=FileReadInteger(f); uchar bytes[];
   if(n<0 || n>16384 || FileTell(f)+(ulong)n>FileSize(f)) return false;
   if(n==0) { value=""; return true; }
   if(FileReadArray(f,bytes,0,n)!=(uint)n) return false;
   value=CharArrayToString(bytes,0,n,CP_UTF8); return true;
}
bool WATWrite(const string path,const WATRecord &e)
{
   string temp=path+".tmp";
   ResetLastError();
   int f=FileOpen(temp,FILE_WRITE|FILE_BIN);
   if(f==INVALID_HANDLE) return WATFileError("record-open",temp,GetLastError());
   ResetLastError();
   FileWriteInteger(f,0x57484131); FileWriteInteger(f,1);
   FileWriteLong(f,e.queued); FileWriteLong(f,e.time); FileWriteLong(f,e.setup); FileWriteLong(f,e.anchor);
   FileWriteDouble(f,e.price); FileWriteDouble(f,e.tip); FileWriteDouble(f,e.head);
   FileWriteInteger(f,e.direction); FileWriteInteger(f,e.pattern);
   FileWriteInteger(f,e.observation); FileWriteInteger(f,e.kind);
   bool ok=WATWriteString(f,e.instance) && WATWriteString(f,e.message) &&
           WATWriteString(f,e.main_photo) && WATWriteString(f,e.lower_photo) && WATWriteString(f,e.parent);
   FileFlush(f); ok=ok && GetLastError()==0;
   int error=GetLastError(); FileClose(f);
   if(!ok) return WATFileError("record-write/flush",temp,error);
   return WATMoveFile(temp,path,FILE_REWRITE);
}
bool WATRead(const string path,WATRecord &e)
{
   int f=FileOpen(path,FILE_READ|FILE_BIN|FILE_SHARE_READ);
   if(f==INVALID_HANDLE) return false;
   ResetLastError();
   bool ok=FileSize(f)>=100 && FileSize(f)<=84000;
   int magic=FileReadInteger(f),schema=FileReadInteger(f);
   e.queued=FileReadLong(f); e.time=FileReadLong(f); e.setup=FileReadLong(f); e.anchor=FileReadLong(f);
   e.price=FileReadDouble(f); e.tip=FileReadDouble(f); e.head=FileReadDouble(f);
   e.direction=FileReadInteger(f); e.pattern=FileReadInteger(f);
   e.observation=FileReadInteger(f); e.kind=FileReadInteger(f);
   ok=ok && magic==0x57484131 && schema==1 &&
      WATReadString(f,e.instance) && WATReadString(f,e.message) &&
      WATReadString(f,e.main_photo) && WATReadString(f,e.lower_photo) && WATReadString(f,e.parent);
   ok=ok && FileTell(f)==FileSize(f) && GetLastError()==0 && e.queued>0 && e.time>=e.setup && e.setup>0 &&
      e.anchor>0 && (e.direction==1 || e.direction==-1) && e.pattern>=1 && e.pattern<=3 &&
      e.observation>=0 && e.observation<=2 && (e.kind==1 || e.kind==2) &&
      MathIsValidNumber(e.price) && e.price>0 && MathIsValidNumber(e.tip) && e.tip>0 &&
      WATSafeName(e.instance) && StringLen(e.message)>0 && StringLen(e.message)<=900 &&
      (e.main_photo=="" || (StringFind(e.main_photo,"WHAshots\\")==0 && StringLen(e.main_photo)<=63 && StringFind(e.main_photo,"..")<0)) &&
      (e.lower_photo=="" || (StringFind(e.lower_photo,"WHAshots\\")==0 && StringLen(e.lower_photo)<=63 && StringFind(e.lower_photo,"..")<0));
   FileClose(f); return ok;
}
bool WATPublish(const string folder,const string id,const WATRecord &e)
{
   return WATExists(folder,id) || WATWrite(folder+"\\"+id+".pending",e);
}

// Durable text receipt is also permission for the detector to begin pictures.
// Separate from .sent: a restart must not re-send text while photos are pending.
bool WATTextAck(const string folder,const string id,long &at)
{
   at=0;
   int f=FileOpen(folder+"\\"+id+".textack",FILE_READ|FILE_BIN|FILE_SHARE_READ);
   if(f==INVALID_HANDLE) return false;
   ResetLastError(); int magic=FileReadInteger(f); long when=FileReadLong(f);
   bool ok=FileSize(f)==12 && magic==0x57415432 && when>0 && GetLastError()==0;
   FileClose(f); if(ok) at=when; return ok;
}
bool WATMarkTextAck(const string folder,const string id)
{
   string path=folder+"\\"+id+".textack",temp=path+".tmp";
   ResetLastError();
   int f=FileOpen(temp,FILE_WRITE|FILE_BIN);
   if(f==INVALID_HANDLE) return WATFileError("textack-open",temp,GetLastError());
   ResetLastError(); FileWriteInteger(f,0x57415432); FileWriteLong(f,(long)TimeLocal());
   FileFlush(f); bool ok=GetLastError()==0 && FileTell(f)==12;
   int error=GetLastError(); FileClose(f);
   if(!ok) return WATFileError("textack-write/flush",temp,error);
   return WATMoveFile(temp,path,0);
}
bool WATPNG(const string path)
{
   int f=FileOpen(path,FILE_READ|FILE_BIN|FILE_SHARE_READ);
   if(f==INVALID_HANDLE) return false;
   uchar b[];
   bool ok=FileSize(f)>100 && FileSize(f)<10000000 && FileReadArray(f,b,0,8)==8 &&
      b[0]==137 && b[1]==80 && b[2]==78 && b[3]==71 && b[4]==13 && b[5]==10 && b[6]==26 && b[7]==10;
   // Reject an unfinished asynchronous screenshot: PNG must end in IEND.
   if(ok)
   {
      FileSeek(f,-12,SEEK_END);
      ok=FileReadArray(f,b,0,12)==12 && b[4]==73 && b[5]==69 && b[6]==78 && b[7]==68;
   }
   FileClose(f); return ok;
}
// A tiny top-level JSON boolean reader: quoted values and nested objects cannot
// masquerade as Telegram's actual top-level ok=true acknowledgement.
bool WATJsonOK(const string json)
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
int WATRetryAfter(const string json)
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
