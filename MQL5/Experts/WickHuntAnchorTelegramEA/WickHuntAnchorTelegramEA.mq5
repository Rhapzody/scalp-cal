#property copyright "MT5 Trading Tools"
#property version "1.07"
#property strict
#property description "WickHuntAnchor 1.12 alerts, chart arrows and text first, then two-TF Telegram pictures. Never opens orders."
#include "AnchorRuntime.mqh"
#include "AnchorTelegramQueue.mqh"
#include "AnchorPresentation.mqh"

input group "Telegram outbox - separate sender handles the network"
input bool InpTelegramEnabled=true; // InpTelegramEnabled | บันทึกสัญญาณส่ง Telegram
input string InpQueueChannel="anchor"; // InpQueueChannel | ช่องคิวตรงกับ Sender
input string InpInstanceID=""; // InpInstanceID | ชื่อชุดตรวจ (ว่าง=อัตโนมัติ)
input bool InpNotifyCancellation=true; // InpNotifyCancellation | แจ้งเมื่อหางยืดแล้วสัญญาณถูกยกเลิก
input group "Two-timeframe pictures"
input bool InpSendPictures=true; // InpSendPictures | ส่งภาพ TF หลักและ TF ย่อย
input int InpPictureWidth=1280; // InpPictureWidth | ความกว้างภาพ (pixels)
input int InpPictureHeight=720; // InpPictureHeight | ความสูงภาพ (pixels)
input int InpMainPictureBars=72; // InpMainPictureBars | จำนวนแท่ง TF หลักในภาพ
input int InpLowerPictureBars=120; // InpLowerPictureBars | จำนวนแท่ง TF ย่อยในภาพ
input int InpPictureWaitSeconds=30; // InpPictureWaitSeconds | เวลารอโหลดกราฟก่อนข้ามภาพ

string g_folder="",g_account="",g_instance="";
int g_instance_lock=INVALID_HANDLE;
long g_watermark=0;
bool g_start_ready=false;
WATRecord g_known[];
struct WATPhotoJob { string id; WATRecord event; };
WATPhotoJob g_jobs[];
long g_photo_started=0;
int g_photo_stage=0;

string EventKey(const long setup,const long time,const long anchor,const int direction)
{
   return WATHash(g_instance+"|"+(string)setup+"|"+(string)time+"|"+(string)anchor+"|"+(string)direction);
}
string RecordKey(const WATRecord &e) { return EventKey(e.setup,e.time,e.anchor,e.direction); }
string EngineKey(const WHAEvent &e) { return EventKey(e.setup_time,e.time,e.anchor_time,e.direction); }
string TFText(const ENUM_TIMEFRAMES tf)
{
   string name=EnumToString(tf); StringReplace(name,"PERIOD_",""); return name;
}
string ConfigurationKey()
{
   return _Symbol+"|"+(string)g_hunt_tf+"|"+(string)InpCheckTF+"|"+(string)InpObservationMode+
      "|"+(string)InpHuntBars+"|"+(string)InpMinHuntPoints+"|"+(string)InpSearchBars+
      "|"+(string)InpAnchorRule+"|"+(string)InpStrongHeadWickPercent+"|"+(string)InpRequireAnchorColor+
      "|"+(string)InpRequireBuyAnchorGreen+"|"+(string)InpRequireSellAnchorRed+
      "|"+(string)InpRequireBodyTouch+"|"+(string)InpMinFVGGapPoints+
      "|"+(string)InpRequireFVGMiddleDirection+"|"+(string)InpRequireFVGDirection+
      "|"+(string)InpEnableBuy+"|"+(string)InpEnableSell+
      "|"+(string)InpHistoryBars+"|"+(string)InpCheckHistoryBars+
      "|"+(string)InpMinSweptWickBodyPercent;
}
bool SaveCheckpoint(const long watermark)
{
   string path=g_folder+"\\"+g_instance+".checkpoint";
   ResetLastError();
   int f=FileOpen(path+".tmp",FILE_WRITE|FILE_BIN);
   if(f==INVALID_HANDLE) return WATFileError("checkpoint-open",path+".tmp",GetLastError());
   ResetLastError(); FileWriteLong(f,watermark); FileFlush(f);
   bool ok=GetLastError()==0 && FileTell(f)==8;
   int error=GetLastError(); FileClose(f);
   if(!ok) return WATFileError("checkpoint-write/flush",path+".tmp",error);
   return WATMoveFile(path+".tmp",path,FILE_REWRITE);
}
int OnInit()
{
#include "AnchorValidation.mqh"
   if(!WATSafeName(InpQueueChannel) || (InpInstanceID!="" && !WATSafeName(InpInstanceID)) ||
      InpCheckTF==PERIOD_CURRENT || PeriodSeconds(InpCheckTF)<=0 || PeriodSeconds(InpCheckTF)>=g_hunt_seconds ||
      InpPictureWidth<640 || InpPictureWidth>2560 || InpPictureHeight<360 || InpPictureHeight>1440 ||
      InpMainPictureBars<10 || InpMainPictureBars>300 || InpLowerPictureBars<10 || InpLowerPictureBars>300 ||
      (long)InpPictureWidth*InpPictureHeight>2000000 ||
      InpPictureWaitSeconds<5 || InpPictureWaitSeconds>120) return INIT_PARAMETERS_INCORRECT;
   g_account=WATAccountKey(); g_folder=WATFolder(InpQueueChannel);
   g_instance=StringSubstr(WATHash(InpInstanceID+"|"+ConfigurationKey()),0,24);
   if(g_folder=="" || g_instance=="") return INIT_FAILED;
   g_instance_lock=FileOpen(g_folder+"\\"+g_instance+".lock",FILE_READ|FILE_WRITE|FILE_BIN);
   if(g_instance_lock==INVALID_HANDLE)
   { Print("WickHuntAnchor EA: duplicate detector or unwritable queue. Use a unique InstanceID for an intentional extra instance."); return INIT_FAILED; }
   Print("WickHuntAnchor EA 1.07 | queue=",InpQueueChannel," | instance=",g_instance,
         " | files=",TerminalInfoString(TERMINAL_DATA_PATH),"\\MQL5\\Files\\",g_folder);
   g_watermark=(long)TimeCurrent();
   int f=FileOpen(g_folder+"\\"+g_instance+".checkpoint",FILE_READ|FILE_BIN);
   if(f!=INVALID_HANDLE)
   {
      long saved=FileReadLong(f);
      if(FileSize(f)==8 && saved>0 && saved<=g_watermark) g_watermark=saved;
      FileClose(f);
   }
   string file; long search=FileFindFirst(g_folder+"\\*.active",file);
   if(search!=INVALID_HANDLE)
   {
      do
      {
         WATRecord e;
         if(WATRead(g_folder+"\\"+file,e) && e.instance==g_instance)
         {
            string id=RecordKey(e);
            // Recover a crash between persisting the active signal and publishing its outbox file.
            if(!WATPublish(g_folder,id,e)) { FileFindClose(search); return INIT_FAILED; }
            int n=ArraySize(g_known); if(ArrayResize(g_known,n+1)!=n+1) { FileFindClose(search); return INIT_FAILED; } g_known[n]=e;
            if(e.main_photo!="" && !FileIsExist(g_folder+"\\"+id+".sent") && !FileIsExist(g_folder+"\\"+id+".photos"))
            { int q=ArraySize(g_jobs); if(ArrayResize(g_jobs,q+1)!=q+1) { FileFindClose(search); return INIT_FAILED; } g_jobs[q].id=id; g_jobs[q].event=e; }
         }
      } while(FileFindNext(search,file));
      FileFindClose(search);
   }
   // Active signals can be finalized while an outbox still awaits network.
   // Recover those photo jobs from pending records as well after a restart.
   search=FileFindFirst(g_folder+"\\*.pending",file);
   if(search!=INVALID_HANDLE)
   {
      do
      {
         WATRecord e;
         if(!WATRead(g_folder+"\\"+file,e) || e.instance!=g_instance || e.kind!=1 || e.main_photo=="") continue;
         string id=StringSubstr(file,0,StringLen(file)-8);
         if(FileIsExist(g_folder+"\\"+id+".photos")) continue;
         bool present=false;
         for(int k=0;k<ArraySize(g_jobs);k++) if(g_jobs[k].id==id) { present=true; break; }
         if(!present)
         { int q=ArraySize(g_jobs); if(ArrayResize(g_jobs,q+1)!=q+1) { FileFindClose(search); return INIT_FAILED; } g_jobs[q].id=id; g_jobs[q].event=e; }
      } while(FileFindNext(search,file));
      FileFindClose(search);
   }
   FolderCreate("WHAshots");
   g_prefix="WHAnchorEA_"+(string)ChartID()+"_";
   if(!ObjectCreate(0,g_prefix+"status",OBJ_LABEL,0,0,0)) return INIT_FAILED;
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_XDISTANCE,12);
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_YDISTANCE,32);
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_COLOR,clrSilver);
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_HIDDEN,true);
   if(!EventSetTimer(1)) return INIT_FAILED;
   Status("Loading history | no orders | configure Anchor Telegram Sender separately");
   return INIT_SUCCEEDED;
}
WATRecord SignalRecord(const WHAEvent &e)
{
   WATRecord r={};
   r.parent=""; r.main_photo=""; r.lower_photo="";
   r.queued=(long)TimeLocal(); r.time=e.time; r.setup=e.setup_time; r.anchor=e.anchor_time;
   r.price=e.price; r.tip=e.signal_tip; r.head=e.head_wick_percent; r.direction=e.direction;
   r.pattern=e.pattern; r.observation=e.observation; r.kind=1; r.instance=g_instance;
   string confirm=e.observation==WHA_LOWER_TF_CLOSE ? "ตรวจเมื่อ "+TFText(InpCheckTF)+" ปิด" :
                  (e.observation==WHA_CLOSED_CANDLE ? "ตรวจเมื่อ "+TFText(g_hunt_tf)+" ปิด" : "ตรวจจากราคาวิ่ง (tick)");
   bool closed=e.observation==WHA_CLOSED_CANDLE || e.time>=e.setup_time+g_hunt_seconds;
   r.message=WAF_HTML_PREFIX+"<b>"+(e.direction==1 ? "🟢 BUY" : "🔴 SELL")+" · "+WAFEscape(_Symbol)+"</b>\n"+
      "WickHunt Anchor · "+TFText(g_hunt_tf)+" → "+TFText(InpCheckTF)+"\n\n"+
      "<b>ราคาเมื่อแจ้ง</b>\n<b>"+WAFPrice(e.price,_Digits)+"</b>\n"+
      "ปลายหางตอนเกิดสัญญาณ · "+WAFPrice(e.signal_tip,_Digits)+"\n\n"+
      "<b>การตรวจสัญญาณ</b>\n"+confirm+" · "+TimeToString((datetime)e.time,TIME_SECONDS)+"\n"+
      "แท่ง "+TFText(g_hunt_tf)+" เริ่ม · "+TimeToString((datetime)e.setup_time,TIME_DATE|TIME_MINUTES)+"\n\n"+
      "<b>"+PatternText(e.pattern)+"</b>\n"+
      "แท่ง Anchor · "+TimeToString((datetime)e.anchor_time,TIME_DATE|TIME_MINUTES);
   // This percentage describes Strong only; it never filters the FVG branch.
   if((e.pattern&2)!=0) r.message+="\nหางหัว Strong · "+DoubleToString(e.head_wick_percent,2)+"%";
   r.message+="\n\n"+(closed ? "✅ แท่ง "+TFText(g_hunt_tf)+" ปิดแล้ว" :
      "⚠️ แท่ง "+TFText(g_hunt_tf)+" ยังไม่ปิด สัญญาณอาจถูกยกเลิก")+
      "\n\n"+TimeToString((datetime)e.time,TIME_DATE)+" · เวลาโบรกเกอร์\n"+
      "<code>#"+WAFShortID(RecordKey(r))+"</code>";
   if((long)TimeCurrent()-e.time>60)
      r.message+="\n⚠️ กู้สัญญาณที่ค้างไว้ โปรดตรวจเวลาโบรกเกอร์";
   if(InpSendPictures)
   {
      string stem="WHAshots\\"+g_account+"_"+StringSubstr(WATHash(InpQueueChannel+"|"+RecordKey(r)),0,24);
      r.main_photo=stem+"_H.png"; r.lower_photo=stem+"_L.png";
   }
   return r;
}
bool ProcessSignals()
{
   WATClearFileError();
   if(!InpTelegramEnabled) return true;
   // A delivered signal cannot be removed from a user's phone. Send an explicit cancellation.
   for(int k=ArraySize(g_known)-1;k>=0;k--)
   {
      WATRecord r=g_known[k]; string id=RecordKey(r); bool exists=false;
      for(int j=ArraySize(g_events)-1;j>=0;j--)
      { if(g_events[j].setup_time<r.setup) break; if(EngineKey(g_events[j])==id) { exists=true; break; } }
      long checked=InpObservationMode==WHA_LOWER_TF_CLOSE ? g_check_last_closed :
                   (InpObservationMode==WHA_CLOSED_CANDLE ? g_last_closed : g_loaded_open);
      // A record outside the loaded historical range cannot be safely cancelled.
      bool covered=ArraySize(g_bars)>0 && r.setup>=g_bars[0].time &&
         (InpObservationMode!=WHA_LOWER_TF_CLOSE || r.setup>=g_check_first);
      if(!exists && covered)
      {
         if(InpNotifyCancellation)
         {
            WATRecord c=r; c.queued=(long)TimeLocal(); c.kind=2; c.main_photo=""; c.lower_photo=""; c.parent=id;
            c.message=WAF_HTML_PREFIX+"<b>❌ ยกเลิก · "+(r.direction==1 ? "BUY" : "SELL")+" · "+WAFEscape(_Symbol)+"</b>\n"+
               "WickHunt Anchor · "+TFText(g_hunt_tf)+" → "+TFText(InpCheckTF)+"\n\n"+
               "หางยืดจนแท่ง Anchor แรกไม่ผ่านเงื่อนไขของสัญญาณเดิม\n"+
               "แท่ง Hunt · "+TimeToString((datetime)r.setup,TIME_DATE|TIME_MINUTES)+" · เวลาโบรกเกอร์\n"+
               "สัญญาณเดิม <code>#"+WAFShortID(id)+"</code>";
            if(!WATPublish(g_folder,WATHash(id+"|cancel"),c)) return false;
         }
      }
      else if(!covered || r.setup+g_hunt_seconds>checked) continue;
      ResetLastError();
      if(!FileDelete(g_folder+"\\"+id+".active"))
         return WATFileError("active-delete",g_folder+"\\"+id+".active",GetLastError());
      for(int j=k;j<ArraySize(g_known)-1;j++) g_known[j]=g_known[j+1];
      if(ArrayResize(g_known,ArraySize(g_known)-1)<0) return false;
   }
   long latest=g_watermark;
   int first=ArraySize(g_events);
   while(first>0 && g_events[first-1].time>g_watermark) first--;
   for(int j=first;j<ArraySize(g_events);j++)
   {
      WHAEvent e=g_events[j];
      WATRecord r=SignalRecord(e); string id=RecordKey(r);
      bool known=false; for(int k=0;k<ArraySize(g_known);k++) if(RecordKey(g_known[k])==id) { known=true; break; }
      if(!known)
      {
         if(!WATWrite(g_folder+"\\"+id+".active",r) || !WATPublish(g_folder,id,r)) return false;
         int n=ArraySize(g_known); if(ArrayResize(g_known,n+1)!=n+1) return false; g_known[n]=r;
         if(InpSendPictures && !FileIsExist(g_folder+"\\"+id+".sent"))
         {
            int q=ArraySize(g_jobs); if(ArrayResize(g_jobs,q+1)!=q+1) return false;
            g_jobs[q].id=id; g_jobs[q].event=r;
         }
      }
      latest=(long)MathMax(latest,e.time);
   }
   long observed=InpObservationMode==WHA_LOWER_TF_CLOSE ? g_check_last_closed :
                 (InpObservationMode==WHA_CLOSED_CANDLE ? g_last_closed : (long)TimeCurrent());
   // Advance the in-memory cursor only after its durable checkpoint commits.
   // On failure, retry the same window; stable IDs/known records prevent duplicates.
   long candidate=(long)MathMax(latest,observed);
   if(!SaveCheckpoint(candidate)) return false;
   g_watermark=candidate;
   return true;
}
#include "AnchorPictures.mqh"
void FinishPictureJob()
{
   g_photo_stage=0; g_photo_started=0;
   for(int j=0;j<ArraySize(g_jobs)-1;j++) g_jobs[j]=g_jobs[j+1];
   ArrayResize(g_jobs,(int)MathMax(0,ArraySize(g_jobs)-1));
}
void UpdatePictures()
{
   if(ArraySize(g_jobs)<1) return;
   // A text still in retry must not block pictures of later accepted texts.
   if(g_photo_stage==0 && g_photo_started==0)
   {
      int ready=-1;
      for(int k=0;k<ArraySize(g_jobs);k++)
      {
         long acknowledged;
         if(FileIsExist(g_folder+"\\"+g_jobs[k].id+".sent") ||
            WATExists(g_folder,WATHash(g_jobs[k].id+"|cancel")) ||
            WATTextAck(g_folder,g_jobs[k].id,acknowledged)) { ready=k; break; }
      }
      if(ready<0) return;
      if(ready>0) { WATPhotoJob swap=g_jobs[0]; g_jobs[0]=g_jobs[ready]; g_jobs[ready]=swap; }
   }
   WATPhotoJob job=g_jobs[0];
   if(FileIsExist(g_folder+"\\"+job.id+".sent")) { FinishPictureJob(); return; }
   // Never spend time rendering before Telegram has accepted the text.
   // Sender and detector share only this flushed acknowledgement file.
   if(WATExists(g_folder,WATHash(job.id+"|cancel"))) { FinishPictureJob(); return; }
   long text_at;
   if(!WATTextAck(g_folder,job.id,text_at)) return;
   if(g_photo_started==0) g_photo_started=(long)TimeLocal();
   if((long)TimeLocal()-g_photo_started>InpPictureWaitSeconds)
   { Print("WickHuntAnchor EA: picture data unavailable; text is already delivered; sender will follow with a missing-images note."); FinishPictureJob(); return; }
   // One image per timer turn. The signal engine remains separate from HTTP.
   if(g_photo_stage==0)
   {
      if(!WAPRender(job.event,g_hunt_tf,job.event.main_photo,InpMainPictureBars)) return;
      g_photo_stage=1; return;
   }
   if(g_photo_stage==1)
   {
      if(!WAPRender(job.event,InpCheckTF,job.event.lower_photo,InpLowerPictureBars)) return;
      g_photo_stage=2;
   }
   if(!WATPNG(job.event.main_photo) || !WATPNG(job.event.lower_photo)) return;
   int f=FileOpen(g_folder+"\\"+job.id+".photos",FILE_WRITE|FILE_BIN);
   if(f==INVALID_HANDLE) return;
   FileWriteInteger(f,1); FileFlush(f); FileClose(f);
   FinishPictureJob();
}
void RunDetector()
{
   if(g_account!=WATAccountKey()) { Status("Account changed: remove and reattach detector"); return; }
   int total=iBars(_Symbol,(ENUM_TIMEFRAMES)_Period);
   long last=(long)iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,0);
   double high=iHigh(_Symbol,(ENUM_TIMEFRAMES)_Period,0),low=iLow(_Symbol,(ENUM_TIMEFRAMES)_Period,0);
   if(total!=g_chart_total || last!=g_chart_last || high!=g_chart_high || low!=g_chart_low) g_display_dirty=true;
   g_chart_total=total; g_chart_last=last; g_chart_high=high; g_chart_low=low;
   // A failed replay can leave a partial array: never publish from it.
   if(!UpdateEngine()) return;
   // Chart display must not wait for the Telegram outbox/checkpoint to recover.
   // Also keep publishing when drawing itself has failed.
   bool drawn=RenderEvents();
   if(g_buffers_dirty || !g_start_ready)
   {
      if(!ProcessSignals())
      {
         Status("Outbox/checkpoint failed | "+WATFileErrorText()+" | retrying | arrows "+
                (drawn ? "updated" : "pending"));
         ChartRedraw(0); return;
      }
      g_buffers_dirty=false;
   }
   if(!drawn) { Status("Drawing failed; retrying"); ChartRedraw(0); return; }
   Status(TFText(g_hunt_tf)+" / "+TFText(InpCheckTF)+" | "+RuleText()+
          (InpObservationMode==WHA_LOWER_TF_CLOSE ?
           (g_wha_quote_ready ? " | sessions OK" : " | sessions unavailable") : "")+" | no orders | "+
          (InpTelegramEnabled ? "queue "+InpQueueChannel : "Telegram off"));
   ChartRedraw(0); g_start_ready=true;
}
void OnTick() { RunDetector(); }
void OnTimer() { RunDetector(); UpdatePictures(); }
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_instance_lock!=INVALID_HANDLE) FileClose(g_instance_lock);
   if(g_prefix!="") ObjectsDeleteAll(0,g_prefix);
   ChartRedraw(0);
}
