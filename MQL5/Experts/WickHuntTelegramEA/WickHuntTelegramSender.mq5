#property copyright "MT5 Trading Tools"
#property version "1.00"
#property strict
#property description "One Telegram sender per terminal/account/channel. Reads WickHuntTelegramEA outbox; never trades."
#include "TelegramQueue.mqh"

input group "Telegram"
input string InpBotToken=""; // Keep private; configured only on the sender
input string InpChatID=""; // Numeric chat ID, negative group ID, or @channel
input string InpQueueChannel="default"; // Same value as all detectors
input group "Delivery"
input int InpTimeoutMs=5000;
input int InpSendIntervalSeconds=2;
input int InpRetryBaseSeconds=5;
input int InpRetryMaxSeconds=300;
input int InpLateAfterSeconds=60;
input bool InpShowStatus=true;

string g_folder="",g_account="",g_prefix="";
int g_lock=INVALID_HANDLE;
long g_not_before=0;
bool g_disabled=false;
ulong g_sent=0,g_errors=0;

void SenderStatus(const string text)
{
   if(InpShowStatus && g_prefix!="") ObjectSetString(0,g_prefix+"owner",OBJPROP_TEXT,"WickHuntTelegramSender | "+text);
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
   if(!WHTSafeName(InpQueueChannel) || !TokenValid(InpBotToken) || StringLen(InpChatID)<1 || StringLen(InpChatID)>128 ||
      InpTimeoutMs<1000 || InpTimeoutMs>30000 || InpSendIntervalSeconds<1 || InpSendIntervalSeconds>60 ||
      InpRetryBaseSeconds<1 || InpRetryBaseSeconds>3600 || InpRetryMaxSeconds<InpRetryBaseSeconds ||
      InpRetryMaxSeconds>86400 || InpLateAfterSeconds<0 || InpLateAfterSeconds>86400)
   { Print("WickHuntTelegramSender: configure BotToken, ChatID, matching QueueChannel and valid delivery Inputs."); return INIT_PARAMETERS_INCORRECT; }
   if(MQLInfoInteger(MQL_TESTER))
   { Print("WickHuntTelegramSender: WebRequest is unavailable in Strategy Tester; attach to a live/demo terminal chart."); return INIT_FAILED; }
   g_account=WHTAccountKey(); g_folder=WHTFolder(InpQueueChannel);
   if(g_folder=="") return INIT_FAILED;
   g_lock=FileOpen(g_folder+"\\sender.lock",FILE_READ|FILE_WRITE|FILE_BIN);
   if(g_lock==INVALID_HANDLE)
   { Print("WickHuntTelegramSender: sender already running for this account/channel, or queue folder is not writable."); return INIT_FAILED; }
   g_prefix="WHTSender_"+(string)ChartID()+"_";
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
   int f=FileOpen(temp,FILE_WRITE|FILE_BIN);
   if(f==INVALID_HANDLE) return false;
   ResetLastError();
   FileWriteInteger(f,0x57485231); FileWriteInteger(f,attempts); FileWriteLong(f,next);
   bool ok=FileTell(f)==16 && GetLastError()==0;
   FileFlush(f); ok=ok && GetLastError()==0;
   FileClose(f);
   return ok && FileMove(temp,0,target,FILE_REWRITE);
}
// Choose the oldest ready event; one HTTP request per timer pass at most.
bool NextEvent(string &name,WSSignal &event,string &message,long &queued,int &attempts)
{
   string file,best="",best_message="";
   long best_time=0;
   int best_attempts=0;
   WSSignal best_event={};
   long search=FileFindFirst(g_folder+"\\*.pending",file);
   if(search==INVALID_HANDLE) return false;
   do
   {
      string id=StringSubstr(file,0,StringLen(file)-8);
      long next; int tries;
      LoadRetry(id,next,tries);
      if((long)TimeLocal()<next) continue;
      WSSignal e; string text; long when;
      if(!WHTRead(g_folder+"\\"+file,e,text,when))
      {
         // Keep corrupt records for inspection; never pretend they were sent.
         if(FileMove(g_folder+"\\"+file,0,g_folder+"\\"+id+".failed",0))
            Print("WickHuntTelegramSender: malformed outbox record retained as .failed: ",id);
         else SenderStatus("Cannot read/move outbox record; check disk permissions");
         continue;
      }
      if(best=="" || when<best_time)
      { best=file; best_time=when; best_message=text; best_event=e; best_attempts=tries; }
   } while(FileFindNext(search,file));
   FileFindClose(search);
   if(best=="") return false;
   name=best; event=best_event; message=best_message; queued=best_time; attempts=best_attempts;
   return true;
}
void OnTimer()
{
   if(g_account!=WHTAccountKey()) { SenderStatus("Account changed: remove and reattach sender"); return; }
   if(g_disabled || (long)TimeLocal()<g_not_before) return;
   string name,message; WSSignal event; long queued; int attempts;
   if(!NextEvent(name,event,message,queued,attempts))
   { SenderStatus("Waiting / retry backoff | sent "+(string)g_sent+" | errors "+(string)g_errors); return; }
   string id=StringSubstr(name,0,StringLen(name)-8);
   if(InpLateAfterSeconds>0 && (long)TimeLocal()-queued>InpLateAfterSeconds)
      message="[DELAYED ALERT - check event time]\n"+message;
   string body="{\"chat_id\":"+WHTJson(InpChatID)+",\"text\":"+WHTJson(message)+"}";
   char data[],response[];
   int n=StringToCharArray(body,data,0,WHOLE_ARRAY,CP_UTF8)-1;
   if(n<1 || ArrayResize(data,n)!=n) { SenderStatus("Cannot allocate Telegram request; retrying"); return; }
   string headers;
   ResetLastError();
   int code=WebRequest("POST","https://api.telegram.org/bot"+InpBotToken+"/sendMessage",
                       "Content-Type: application/json\r\n",InpTimeoutMs,data,response,headers);
   int error=GetLastError();
   string result=CharArrayToString(response,0,ArraySize(response),CP_UTF8);
   g_not_before=(long)TimeLocal()+InpSendIntervalSeconds;
   if(code==200 && WHTJsonOK(result))
   {
      if(!FileMove(g_folder+"\\"+name,0,g_folder+"\\"+id+".sent",0))
      {
         g_disabled=true;
         Print("WickHuntTelegramSender: Telegram accepted an alert but local acknowledgement failed. Sender paused; inspect outbox before restarting. Event: ",id);
         SenderStatus("PAUSED: acknowledgement disk error; inspect outbox");
         return;
      }
      FileDelete(g_folder+"\\"+id+".retry");
      g_sent++; SenderStatus("Sent | total "+(string)g_sent+" | "+TimeToString(TimeLocal(),TIME_SECONDS));
      return;
   }
   g_errors++;
   // Authentication / destination errors affect all events. Preserve the queue
   // and pause until corrected Inputs cause reinitialization.
   if(code==400 || code==401 || code==403 || code==404)
   {
      g_disabled=true;
      Print("WickHuntTelegramSender paused: HTTP ",code,". Check BotToken, ChatID and bot permissions. Queue retained.");
      SenderStatus("PAUSED: HTTP "+IntegerToString(code)+"; fix bot/chat settings");
      return;
   }
   int wait=InpRetryBaseSeconds;
   for(int i=0;i<attempts && wait<InpRetryMaxSeconds;i++) wait=(int)MathMin(InpRetryMaxSeconds,(long)wait*2);
   if(code==429) wait=(int)MathMax(wait,WHTRetryAfter(result));
   long next=(long)TimeLocal()+wait;
   if(code==429) g_not_before=next;
   if(!SaveRetry(id,next,(int)MathMin(1000000,attempts+1)))
   {
      g_disabled=true;
      SenderStatus("PAUSED: retry checkpoint disk error; queue retained");
      Print("WickHuntTelegramSender: cannot persist retry state; sender paused, queue retained.");
      return;
   }
   // Do not print the request URL, token, chat ID or response body.
   Print("WickHuntTelegramSender: HTTP ",code," / MT5 error ",error,"; retry in ",wait,"s. Event: ",id);
   SenderStatus("Retry in "+IntegerToString(wait)+"s | HTTP "+IntegerToString(code)+" / error "+IntegerToString(error));
}
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_lock!=INVALID_HANDLE) FileClose(g_lock);
   if(g_prefix!="") ObjectsDeleteAll(0,g_prefix);
   ChartRedraw(0);
}
