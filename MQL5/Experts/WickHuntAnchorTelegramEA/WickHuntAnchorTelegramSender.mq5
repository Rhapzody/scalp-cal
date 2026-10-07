#property copyright "MT5 Trading Tools"
#property version "1.07"
#property strict
#property description "One Telegram sender per terminal/account/channel. Text first, then pictures from WickHuntAnchorTelegramEA outbox; never trades."
#include "AnchorTelegramQueue.mqh"
#include "AnchorPresentation.mqh"

input group "Telegram"
input string InpBotToken=""; // InpBotToken | Token บอท เก็บไว้เฉพาะ Sender
input string InpChatID=""; // InpChatID | Chat ID ปลายทาง
input string InpQueueChannel="anchor"; // InpQueueChannel | ช่องคิวตรงกับ EA ตรวจสัญญาณ
input group "Delivery"
input int InpTimeoutMs=15000; // InpTimeoutMs | เวลารอ Telegram (milliseconds)
input int InpSendIntervalSeconds=2; // InpSendIntervalSeconds | เว้นระหว่างส่ง (วินาที)
input int InpRetryBaseSeconds=5; // InpRetryBaseSeconds | รอเริ่มต้นก่อนส่งซ้ำ (วินาที)
input int InpRetryMaxSeconds=300; // InpRetryMaxSeconds | รอส่งซ้ำสูงสุด (วินาที)
input int InpLateAfterSeconds=60; // InpLateAfterSeconds | เกินเวลานี้ระบุ DELAYED (วินาที)
input bool InpShowStatus=true; // InpShowStatus | แสดงสถานะ Sender บนกราฟ
input int InpPhotoWaitSeconds=45; // InpPhotoWaitSeconds | รอรูปหลังข้อความสำเร็จ (วินาที)
input bool InpDeleteSentPictures=true; // InpDeleteSentPictures | ลบภาพที่ส่งแล้วเพื่อประหยัดพื้นที่

string g_folder="",g_account="",g_prefix="";
int g_lock=INVALID_HANDLE;
long g_not_before=0;
bool g_disabled=false;
ulong g_sent=0,g_errors=0;

void SenderStatus(const string text)
{
   if(InpShowStatus && g_prefix!="") ObjectSetString(0,g_prefix+"owner",OBJPROP_TEXT,"WickHuntAnchorTelegramSender | "+text);
}
bool TokenValid(const string token)
{
   int colon=StringFind(token,":");
   if(colon<1 || colon>=StringLen(token)-1 || StringLen(token)>256) return false;
   for(int i=0;i<StringLen(token);i++)
   {
      ushort c=StringGetCharacter(token,i);
      if(i<colon && !(c>='0' && c<='9')) return false;
      if(i>colon && !((c>='a' && c<='z') || (c>='A' && c<='Z') || (c>='0' && c<='9') || c=='_' || c=='-')) return false;
   }
   return true;
}
int OnInit()
{
   if(!WATSafeName(InpQueueChannel) || !TokenValid(InpBotToken) || StringLen(InpChatID)<1 || StringLen(InpChatID)>128 ||
      InpTimeoutMs<1000 || InpTimeoutMs>30000 || InpSendIntervalSeconds<1 || InpSendIntervalSeconds>60 ||
      InpRetryBaseSeconds<1 || InpRetryBaseSeconds>3600 || InpRetryMaxSeconds<InpRetryBaseSeconds ||
      InpRetryMaxSeconds>86400 || InpLateAfterSeconds<0 || InpLateAfterSeconds>86400 || InpPhotoWaitSeconds<5 || InpPhotoWaitSeconds>600)
   { Print("WickHuntAnchorTelegramSender: configure BotToken, ChatID, matching QueueChannel and valid delivery Inputs."); return INIT_PARAMETERS_INCORRECT; }
   if(MQLInfoInteger(MQL_TESTER))
   { Print("WickHuntAnchorTelegramSender: WebRequest is unavailable in Strategy Tester; attach to a live/demo terminal chart."); return INIT_FAILED; }
   g_account=WATAccountKey(); g_folder=WATFolder(InpQueueChannel);
   if(g_folder=="") return INIT_FAILED;
   g_lock=FileOpen(g_folder+"\\sender.lock",FILE_READ|FILE_WRITE|FILE_BIN);
   if(g_lock==INVALID_HANDLE)
   { Print("WickHuntAnchorTelegramSender: sender already running for this account/channel, or queue folder is not writable."); return INIT_FAILED; }
   g_prefix="WATSender_"+(string)ChartID()+"_";
   if(InpShowStatus)
   {
      if(!ObjectCreate(0,g_prefix+"owner",OBJ_LABEL,0,0,0)) return INIT_FAILED;
      ObjectSetInteger(0,g_prefix+"owner",OBJPROP_CORNER,CORNER_LEFT_LOWER);
      ObjectSetInteger(0,g_prefix+"owner",OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0,g_prefix+"owner",OBJPROP_XDISTANCE,12);
      ObjectSetInteger(0,g_prefix+"owner",OBJPROP_YDISTANCE,16);
      ObjectSetInteger(0,g_prefix+"owner",OBJPROP_COLOR,clrSilver);
      ObjectSetInteger(0,g_prefix+"owner",OBJPROP_FONTSIZE,9);
      ObjectSetInteger(0,g_prefix+"owner",OBJPROP_HIDDEN,true);
   }
   if(!EventSetTimer(1)) return INIT_FAILED;
   SenderStatus("Ready | channel "+InpQueueChannel+" | allow https://api.telegram.org in MT5 WebRequest settings");
   return INIT_SUCCEEDED;
}
void LoadRetry(const string id,long &next,int &attempts)
{
   next=0; attempts=0;
   int f=FileOpen(g_folder+"\\"+id+".retry",FILE_READ|FILE_BIN);
   if(f==INVALID_HANDLE) return;
   ResetLastError();
   int magic=FileReadInteger(f),a=FileReadInteger(f);
   long n=FileReadLong(f);
   if(FileSize(f)==16 && magic==0x57485231 && a>=0 && a<=1000000 && n>=0 && GetLastError()==0)
   { next=n; attempts=a; }
   FileClose(f);
}
bool SaveRetry(const string id,const long next,const int attempts)
{
   string target=g_folder+"\\"+id+".retry",temp=target+".tmp";
   ResetLastError();
   int f=FileOpen(temp,FILE_WRITE|FILE_BIN);
   if(f==INVALID_HANDLE) return WATFileError("retry-open",temp,GetLastError());
   ResetLastError();
   FileWriteInteger(f,0x57485231); FileWriteInteger(f,attempts); FileWriteLong(f,next);
   bool ok=FileTell(f)==16 && GetLastError()==0;
   FileFlush(f); ok=ok && GetLastError()==0;
   int error=GetLastError(); FileClose(f);
   if(!ok) return WATFileError("retry-write/flush",temp,error);
   return WATMoveFile(temp,target,FILE_REWRITE);
}

enum ENUM_WAT_DELIVERY { WAT_TEXT=0, WAT_ALBUM=1, WAT_NO_PICTURES=2, WAT_SKIP_CANCELLED=3 };
string RetryKey(const string id,const int phase)
{ return id+(phase==WAT_TEXT ? "_text" : "_pictures"); }
bool NextEvent(string &name,WATRecord &event,int &phase,int &attempts)
{
   string file,best=""; long best_time=0; int best_priority=9,best_phase=WAT_TEXT,best_tries=0;
   WATRecord best_event={};
   long search=FileFindFirst(g_folder+"\\*.pending",file);
   if(search==INVALID_HANDLE) return false;
   do
   {
      string id=StringSubstr(file,0,StringLen(file)-8);
      WATRecord e;
      if(!WATRead(g_folder+"\\"+file,e))
      {
         if(FileMove(g_folder+"\\"+file,0,g_folder+"\\"+id+".failed",0))
            Print("WickHuntAnchorTelegramSender: malformed outbox retained as .failed: ",id);
         else SenderStatus("Cannot read/move outbox record; check disk permissions");
         continue;
      }
      // Cancellation waits for the original TEXT, not its picture upload.
      long parent_ack;
      if(e.parent!="" && FileIsExist(g_folder+"\\"+e.parent+".pending") &&
         !WATTextAck(g_folder,e.parent,parent_ack)) continue;
      long ack;
      bool text_sent=WATTextAck(g_folder,id,ack);
      if(!text_sent && FileIsExist(g_folder+"\\"+id+".textack"))
      { g_disabled=true; SenderStatus("PAUSED: corrupt text receipt; inspect outbox"); break; }
      int mode=WAT_TEXT,priority=0;
      if(text_sent)
      {
         priority=1;
         if(WATExists(g_folder,WATHash(id+"|cancel"))) mode=WAT_SKIP_CANCELLED;
         else if(e.main_photo=="") mode=WAT_SKIP_CANCELLED;
         else if(FileIsExist(g_folder+"\\"+id+".picture_failed")) mode=WAT_NO_PICTURES;
         else if(FileIsExist(g_folder+"\\"+id+".photos") && WATPNG(e.main_photo) && WATPNG(e.lower_photo)) mode=WAT_ALBUM;
         else if((long)TimeLocal()-ack>=InpPhotoWaitSeconds) mode=WAT_NO_PICTURES;
         else continue;
      }
      long next; int tries;
      LoadRetry(RetryKey(id,mode),next,tries);
      if(mode!=WAT_SKIP_CANCELLED && (long)TimeLocal()<next) continue;
      // Every ready text/cancellation outranks every album in this channel.
      if(best=="" || priority<best_priority || (priority==best_priority && e.queued<best_time) ||
         (priority==best_priority && e.queued==best_time && e.kind<best_event.kind))
      { best=file; best_time=e.queued; best_event=e; best_phase=mode; best_priority=priority; best_tries=tries; }
   } while(FileFindNext(search,file));
   FileFindClose(search);
   if(best=="" || g_disabled) return false;
   name=best; event=best_event; phase=best_phase; attempts=best_tries; return true;
}
bool CompleteEvent(const string name,const WATRecord &event)
{
   string id=StringSubstr(name,0,StringLen(name)-8);
   if(!WATMoveFile(g_folder+"\\"+name,g_folder+"\\"+id+".sent",0))
   {
      g_disabled=true; SenderStatus("PAUSED: acknowledgement disk error; inspect outbox");
      Print("WickHuntAnchorTelegramSender: cannot acknowledge completed delivery; inspect event ",id);
      return false;
   }
   FileDelete(g_folder+"\\"+id+".retry"); // old 1.00 retry, if any
   FileDelete(g_folder+"\\"+id+"_text.retry"); FileDelete(g_folder+"\\"+id+"_pictures.retry");
   FileDelete(g_folder+"\\"+id+".picture_failed");
   // Keep .textack for deduplication and to establish delivery before CANCELLED.
   if(InpDeleteSentPictures)
   {
      if(event.main_photo!="") FileDelete(event.main_photo);
      if(event.lower_photo!="") FileDelete(event.lower_photo);
      FileDelete(g_folder+"\\"+id+".photos");
   }
   return true;
}

bool AppendText(char &out[],const string text)
{
   char bytes[]; int n=StringToCharArray(text,bytes,0,WHOLE_ARRAY,CP_UTF8)-1,old=ArraySize(out);
   if(n<0 || ArrayResize(out,old+n)!=old+n) return false;
   return n==0 || ArrayCopy(out,bytes,old,0,n)==n;
}
bool AppendPhoto(char &out[],const string path)
{
   int f=FileOpen(path,FILE_READ|FILE_BIN|FILE_SHARE_READ);
   if(f==INVALID_HANDLE) return false;
   int n=(int)FileSize(f),old=ArraySize(out);
   bool ok=n>100 && n<10000000 && ArrayResize(out,old+n)==old+n && FileReadArray(f,out,old,n)==(uint)n;
   FileClose(f); return ok;
}
bool AlbumRequest(const string chat,const string message,const string first,const string second,
                  const string boundary,char &out[])
{
   ArrayResize(out,0);
   string media="[{\"type\":\"photo\",\"media\":\"attach://main\",\"caption\":"+WATJson(message)+
                ",\"parse_mode\":\"HTML\"},{\"type\":\"photo\",\"media\":\"attach://lower\"}]";
   string part="--"+boundary+"\r\nContent-Disposition: form-data; name=\"";
   if(!AppendText(out,part+"chat_id\"\r\n\r\n"+chat+"\r\n"+
                      part+"media\"\r\n\r\n"+media+"\r\n")) return false;
   if(!AppendText(out,part+"main\"; filename=\"main.png\"\r\nContent-Type: image/png\r\n\r\n") ||
      !AppendPhoto(out,first) || !AppendText(out,"\r\n")) return false;
   return AppendText(out,part+"lower\"; filename=\"lower.png\"\r\nContent-Type: image/png\r\n\r\n") &&
          AppendPhoto(out,second) && AppendText(out,"\r\n--"+boundary+"--\r\n");
}


void OnTimer()
{
   if(g_account!=WATAccountKey()) { SenderStatus("Account changed: remove and reattach sender"); return; }
   if(g_disabled || (long)TimeLocal()<g_not_before) return;
   string name; WATRecord event; int phase,attempts;
   if(!NextEvent(name,event,phase,attempts))
   { if(!g_disabled) SenderStatus("Waiting / retry | requests sent "+(string)g_sent+" | errors "+(string)g_errors); return; }
   string id=StringSubstr(name,0,StringLen(name)-8);
   if(phase==WAT_SKIP_CANCELLED)
   { CompleteEvent(name,event); return; }
   string message=WAFMessageHTML(event.message);
   if(phase==WAT_TEXT && InpLateAfterSeconds>0 && (long)TimeLocal()-event.queued>InpLateAfterSeconds)
      message="⚠️ <b>แจ้งเตือนล่าช้า โปรดตรวจเวลาสัญญาณ</b>\n\n"+message;
   if(phase==WAT_ALBUM) message=WAFAlbumCaption(event,id);
   if(phase==WAT_NO_PICTURES)
      message="📷 <b>รูปยังไม่พร้อม</b>\nข้อความสัญญาณส่งแล้ว โปรดเปิดกราฟตรวจสอบ\n<code>#"+WAFShortID(id)+"</code>";
   char data[],response[];
   string method="sendMessage",request_headers="Content-Type: application/json\r\n";
   if(phase==WAT_ALBUM)
   {
      string boundary="WHA_"+id;
      if(!AlbumRequest(InpChatID,message,event.main_photo,event.lower_photo,boundary,data))
      { SenderStatus("Cannot allocate/read album; retained for retry"); return; }
      method="sendMediaGroup"; request_headers="Content-Type: multipart/form-data; boundary="+boundary+"\r\n";
   }
   else
   {
      string body="{\"chat_id\":"+WATJson(InpChatID)+",\"text\":"+WATJson(message)+",\"parse_mode\":\"HTML\"}";
      int n=StringToCharArray(body,data,0,WHOLE_ARRAY,CP_UTF8)-1;
      if(n<1 || ArrayResize(data,n)!=n) { SenderStatus("Cannot allocate Telegram request; retrying"); return; }
   }
   string headers; ResetLastError();
   int code=WebRequest("POST","https://api.telegram.org/bot"+InpBotToken+"/"+method,
                       request_headers,InpTimeoutMs,data,response,headers);
   int error=GetLastError();
   string result=CharArrayToString(response,0,ArraySize(response),CP_UTF8);
   g_not_before=(long)TimeLocal()+InpSendIntervalSeconds;
   if(code==200 && WATJsonOK(result))
   {
      if(phase==WAT_TEXT)
      {
         if(!WATMarkTextAck(g_folder,id))
         {
            g_disabled=true; SenderStatus("PAUSED: Telegram accepted text; receipt write failed");
            Print("WickHuntAnchorTelegramSender: text accepted but receipt could not be persisted; inspect event ",id);
            return;
         }
         FileDelete(g_folder+"\\"+id+"_text.retry");
         if(event.main_photo=="" && !CompleteEvent(name,event)) return;
         SenderStatus("Text sent first | waiting for pictures | ID "+id);
      }
      else
      {
         if(!CompleteEvent(name,event)) return;
         SenderStatus(phase==WAT_ALBUM ? "Album sent after text" : "Missing-pictures notice sent; original text retained");
      }
      g_sent++; return;
   }
   g_errors++;
   // A malformed album must not pause otherwise deliverable signal texts.
   if(code==400 && phase==WAT_ALBUM)
   {
      int f=FileOpen(g_folder+"\\"+id+".picture_failed",FILE_WRITE|FILE_BIN);
      if(f==INVALID_HANDLE) { g_disabled=true; SenderStatus("PAUSED: cannot save album failure state"); return; }
      ResetLastError(); FileWriteInteger(f,400); FileFlush(f); bool ok=GetLastError()==0; FileClose(f);
      if(!ok) { g_disabled=true; SenderStatus("PAUSED: album failure checkpoint error"); return; }
      FileDelete(g_folder+"\\"+id+"_pictures.retry");
      SenderStatus("Album rejected; text already sent, follow-up notice queued"); return;
   }
   if(code==400 || code==401 || code==403 || code==404)
   {
      g_disabled=true;
      Print("WickHuntAnchorTelegramSender paused: HTTP ",code,". Check bot/chat settings; queue retained.");
      SenderStatus("PAUSED: HTTP "+IntegerToString(code)+"; fix bot/chat settings"); return;
   }
   int wait=InpRetryBaseSeconds;
   for(int i=0;i<attempts && wait<InpRetryMaxSeconds;i++) wait=(int)MathMin(InpRetryMaxSeconds,(long)wait*2);
   if(code==429) wait=(int)MathMax(wait,WATRetryAfter(result));
   long next=(long)TimeLocal()+wait;
   if(code==429) g_not_before=next;
   if(!SaveRetry(RetryKey(id,phase),next,(int)MathMin(1000000,attempts+1)))
   {
      g_disabled=true; SenderStatus("PAUSED: retry checkpoint disk error; queue retained"); return;
   }
   Print("WickHuntAnchorTelegramSender: HTTP ",code," / MT5 error ",error,"; retry phase ",phase," in ",wait,"s. ID ",id);
   SenderStatus("Retry "+(phase==WAT_TEXT ? "text" : "pictures")+" in "+(string)wait+"s | HTTP "+(string)code);
}
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_lock!=INVALID_HANDLE) FileClose(g_lock);
   if(g_prefix!="") ObjectsDeleteAll(0,g_prefix);
   ChartRedraw(0);
}
