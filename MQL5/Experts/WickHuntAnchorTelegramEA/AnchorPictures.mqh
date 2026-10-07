#ifndef WHA_ALERT_PICTURES
#define WHA_ALERT_PICTURES
#include <Canvas/Canvas.mqh>
// Render market OHLC in memory. No ChartOpen/default.tpl, extra EA, chart
// switching or changes to the user's chart. PNG uses lossless stored DEFLATE.
void WAPBigEndian(uchar &out[],const int at,const uint v)
{ out[at]=(uchar)(v>>24); out[at+1]=(uchar)(v>>16); out[at+2]=(uchar)(v>>8); out[at+3]=(uchar)v; }
uint WAPCRC(const uchar &bytes[],const int at,const int count)
{
   uint table[256];
   for(int n=0;n<256;n++)
   { uint c=(uint)n; for(int k=0;k<8;k++) c=(c&1)!=0 ? 0xedb88320^(c>>1) : c>>1; table[n]=c; }
   uint crc=0xffffffff;
   for(int i=at;i<at+count;i++) crc=table[(crc^bytes[i])&255]^(crc>>8);
   return crc^0xffffffff;
}
bool WAPChunk(uchar &png[],const string type,const uchar &payload[])
{
   int n=ArraySize(payload),at=ArraySize(png);
   if(ArrayResize(png,at+n+12)!=at+n+12) return false;
   WAPBigEndian(png,at,(uint)n);
   for(int j=0;j<4;j++) png[at+4+j]=(uchar)StringGetCharacter(type,j);
   if(n>0 && ArrayCopy(png,payload,at+8,0,n)!=n) return false;
   WAPBigEndian(png,at+n+8,WAPCRC(png,at+4,n+4)); return true;
}
class CWAPCanvas : public CCanvas
{
public:
   bool SavePNG(const string path)
   {
      uchar raw[],zlib[],png[],ihdr[],empty[];
      int stride=m_width*3+1,size=stride*m_height;
      if(size<=0 || ArrayResize(raw,size)!=size) return false;
      uint adler_a=1,adler_b=0;
      int p=0;
      for(int y=0;y<m_height;y++)
      {
         raw[p++]=0; // PNG filter None
         for(int x=0;x<m_width;x++)
         {
            uint pixel=m_pixels[y*m_width+x];
            raw[p++]=(uchar)(pixel>>16); raw[p++]=(uchar)(pixel>>8); raw[p++]=(uchar)pixel;
         }
      }
      for(int i=0;i<size;i++) { adler_a=(adler_a+raw[i])%65521; adler_b=(adler_b+adler_a)%65521; }
      int blocks=(size+65534)/65535,zsize=size+blocks*5+6;
      if(ArrayResize(zlib,zsize)!=zsize) return false;
      zlib[0]=0x78; zlib[1]=0x01; p=2;
      for(int at=0;at<size;)
      {
         int n=(int)MathMin(65535,size-at),inverse=65535-n;
         zlib[p++]=(uchar)(at+n==size ? 1 : 0); // BFINAL, BTYPE=00, byte aligned
         zlib[p++]=(uchar)n; zlib[p++]=(uchar)(n>>8);
         zlib[p++]=(uchar)inverse; zlib[p++]=(uchar)(inverse>>8);
         if(ArrayCopy(zlib,raw,p,at,n)!=n) return false;
         p+=n; at+=n;
      }
      WAPBigEndian(zlib,p,(adler_b<<16)|adler_a);
      if(ArrayResize(png,8)!=8 || ArrayResize(ihdr,13)!=13) return false;
      uchar signature[8]={137,80,78,71,13,10,26,10}; ArrayCopy(png,signature);
      ArrayInitialize(ihdr,0); WAPBigEndian(ihdr,0,(uint)m_width); WAPBigEndian(ihdr,4,(uint)m_height);
      ihdr[8]=8; ihdr[9]=2; // true-ink RGB, 8 bits per channel
      if(!WAPChunk(png,"IHDR",ihdr) || !WAPChunk(png,"IDAT",zlib) || !WAPChunk(png,"IEND",empty)) return false;
      int f=FileOpen(path+".tmp",FILE_WRITE|FILE_BIN);
      if(f==INVALID_HANDLE) return false;
      ResetLastError(); bool ok=FileWriteArray(f,png)==(uint)ArraySize(png);
      FileFlush(f); ok=ok && GetLastError()==0; FileClose(f);
      return ok && FileMove(path+".tmp",0,path,FILE_REWRITE);
   }
};
int WAPY(const double price,const double bottom,const double span,const int top,const int height)
{ return top+height-(int)MathRound((price-bottom)/span*height); }
bool WAPText(CWAPCanvas &canvas,const int x,const int y,const string text,
             const int available,const int size,const uint ink,const bool bold=false)
{
   // Positive sizes are image pixels, independent of the Wine/Windows DPI.
   if(!canvas.FontSet("Arial",size,bold ? FW_SEMIBOLD : FW_NORMAL)) return false;
   string fitted=text;
   if((int)canvas.TextWidth(fitted)>available)
   {
      while(StringLen(fitted)>0 && (int)canvas.TextWidth(fitted+"...")>available)
         fitted=StringSubstr(fitted,0,StringLen(fitted)-1);
      fitted+="...";
   }
   canvas.TextOut(x,y,fitted,ink); return true;
}
bool WAPRender(const WATRecord &e,const ENUM_TIMEFRAMES tf,const string path,const int requested)
{
   MqlRates rates[]; ArraySetAsSeries(rates,false);
   if(!SeriesInfoInteger(_Symbol,tf,SERIES_SYNCHRONIZED)) return false;
   int n=CopyRates(_Symbol,tf,0,requested,rates);
   if(n<2) return false;
   CWAPCanvas canvas;
   if(!canvas.Create("WHA_memory_"+(string)GetMicrosecondCount(),InpPictureWidth,InpPictureHeight)) return false;
   uint background=0xff101d27,panel=0xff162631,grid=0xff2b3d49;
   uint muted=0xffb1c3d0,white=0xffeef4f8,gold=0xffe3bd59;
   uint direction_ink=ColorToARGB(e.direction==1 ? InpBuyColor : InpSellColor);
   canvas.Erase(background);
   double scale=MathMin((double)InpPictureWidth/1280.0,(double)InpPictureHeight/720.0);
   int margin=(int)MathRound(28*scale),title_size=(int)MathMax(24,48*scale);
   int text_size=(int)MathMax(18,34*scale),axis_size=(int)MathMax(16,32*scale);
   int small_size=(int)MathMax(16,28*scale),line_height=text_size+10;
   string id=RecordKey(e),side=e.direction==1 ? "BUY" : "SELL";
   bool main=tf==g_hunt_tf;
   canvas.FillRectangle(0,0,InpPictureWidth-1,margin+title_size+line_height*2,panel);
   int tag_width=(int)MathRound(200*scale);
   if(!WAPText(canvas,margin,margin,_Symbol+" · "+TFText(tf),
               InpPictureWidth-margin*2-tag_width,title_size,white,true)) return false;
   WAPText(canvas,InpPictureWidth-margin-tag_width,margin,main ? "MAIN TF" : "CHECK TF",
           tag_width,text_size,muted);
   int row=margin+title_size+12;
   WAPText(canvas,margin,row,side+" · "+TimeToString((datetime)e.time,TIME_DATE|TIME_SECONDS)+
           " broker · #"+WAFShortID(id),InpPictureWidth-margin*2,text_size,direction_ink,true);
   row+=line_height;
   WAPText(canvas,margin,row,PatternText(e.pattern)+" · Signal price "+WAFPrice(e.price,_Digits)+
           " · Wick tip "+WAFPrice(e.tip,_Digits),InpPictureWidth-margin*2,text_size,muted);
   if(!canvas.FontSet("Arial",axis_size)) return false;
   int price_width=(int)canvas.TextWidth(DoubleToString(e.tip,_Digits));
   int left=margin,top=row+line_height+margin;
   int width=InpPictureWidth-left-margin-(int)MathMax(110*scale,price_width+margin);
   int height=InpPictureHeight-top-margin-small_size*3-30;
   if(width<100 || height<50) return false;
   double low=rates[0].low,high=rates[0].high;
   for(int i=0;i<n;i++)
   {
      WHABar b={(long)rates[i].time,rates[i].open,rates[i].high,rates[i].low,rates[i].close};
      if(!WHAValid(b)) return false;
      low=MathMin(low,b.low); high=MathMax(high,b.high);
   }
   low=MathMin(low,e.tip); high=MathMax(high,e.tip);
   double range=high-low;
   if(range<=0) return false;
   low-=range*0.12; high+=range*0.12; range=high-low;
   double step=(double)width/(n+3);
   int body=(int)MathMax(1,MathMin(14*scale,step*0.30));
   int tip_y=WAPY(e.tip,low,range,top,height);
   for(int k=0;k<=2;k++)
   {
      double price=low+range*k/2.0; int y=WAPY(price,low,range,top,height);
      canvas.LineHorizontal(left,left+width,y,grid);
      // Keep the frozen wick price readable if it sits near a grid label.
      if(!InpShowAnchorLinks || MathAbs(y-tip_y)>axis_size+8)
         WAPText(canvas,left+width+10,y-axis_size/2,DoubleToString(price,_Digits),
                 InpPictureWidth-left-width-margin-10,axis_size,muted);
   }
   int confirm=-1,anchor=-1,signal_x=-1;
   int tf_seconds=PeriodSeconds(tf);
   long plotted=e.observation==WHA_LIVE_TICK ? e.time : e.time-1;
   for(int i=0;i<n;i++)
   {
      MqlRates b=rates[i]; int x=left+(int)MathRound((i+0.5)*step);
      int yo=WAPY(b.open,low,range,top,height),yc=WAPY(b.close,low,range,top,height);
      int yh=WAPY(b.high,low,range,top,height),yl=WAPY(b.low,low,range,top,height);
      uint ink=ColorToARGB(b.close>=b.open ? InpBuyColor : InpSellColor);
      canvas.LineVertical(x,yh,yl,ink);
      canvas.FillRectangle(x-body,(int)MathMin(yo,yc),x+body,(int)MathMax(MathMin(yo,yc)+1,MathMax(yo,yc)),ink);
      if(plotted>=(long)b.time && plotted<(long)b.time+PeriodSeconds(tf)) confirm=i;
      if(e.anchor>=(long)b.time && e.anchor<(long)b.time+PeriodSeconds(tf)) anchor=i;
      // Timestamp stays at the actual signal instant, not main candle Open.
      // Interpolate within a main candle; a close on the boundary is its next Open.
      if(e.time>=(long)b.time && (e.time<(long)b.time+tf_seconds ||
         (i==n-1 && e.time==(long)b.time+tf_seconds)))
         signal_x=left+(int)MathRound((i+0.5+(double)(e.time-(long)b.time)/tf_seconds)*step);
   }
   // Three compact date/time ticks; measure each label and keep it in bounds.
   if(!canvas.FontSet("Arial",small_size)) return false;
   for(int k=0;k<3;k++)
   {
      int i=(int)MathRound((n-1)*k/2.0);
      string label=TimeToString(rates[i].time,TIME_DATE|TIME_MINUTES);
      label=StringSubstr(label,5); // MM.DD HH:MM, broker date across sessions
      int x=left+(int)MathRound((i+0.5)*step),label_width=(int)canvas.TextWidth(label);
      if(k==1 && (n<3 || width<label_width*3+margin*2)) continue;
      x=(int)MathMax(left,MathMin(left+width-label_width,x-label_width/2));
      canvas.TextOut(x,top+height+12,label,muted);
   }
   int from=anchor>=0 ? left+(int)MathRound((anchor+0.5)*step) : left;
   int to=signal_x>=0 ? signal_x : left+width;
   if(InpShowAnchorLinks)
   {
      uint link=ColorToARGB(InpAnchorColor);
      int dash=(int)MathMax(4,12*scale),gap=(int)MathMax(3,8*scale);
      for(int x=from;x<=to;x+=dash+gap)
         canvas.LineHorizontal(x,(int)MathMin(to,x+dash),tip_y,link);
      WAPText(canvas,left+width+10,tip_y-axis_size/2,DoubleToString(e.tip,_Digits),
              InpPictureWidth-left-width-margin-10,axis_size,white,true);
   }
   if(anchor>=0 && tf==g_hunt_tf)
   {
      int x=left+(int)MathRound((anchor+0.5)*step);
      canvas.Rectangle(x-body-3,WAPY(rates[anchor].high,low,range,top,height)-3,
                       x+body+3,WAPY(rates[anchor].low,low,range,top,height)+3,gold);
   }
   if(confirm>=0)
   {
      int x=left+(int)MathRound((confirm+0.5)*step);
      int y=WAPY(e.direction==1 ? rates[confirm].low : rates[confirm].high,low,range,top,height);
      int sign=e.direction==1 ? 1 : -1;
      int arrow=(int)MathMax(6,12*scale);
      y+=sign*(arrow+8);
      canvas.FillTriangle(x,y-sign*arrow,x-arrow,y+sign*arrow/2,x+arrow,y+sign*arrow/2,direction_ink);
      canvas.LineVertical(x,y+sign*arrow/2,y+sign*arrow*2,direction_ink);
   }
   string legend=main ? "Gold box: Anchor "+TimeToString((datetime)e.anchor,TIME_DATE|TIME_MINUTES) :
      (e.observation==WHA_LOWER_TF_CLOSE ? "Arrow: checked at "+TFText(InpCheckTF)+" close" :
       (e.observation==WHA_CLOSED_CANDLE ? "Arrow: checked at main-TF close" : "Arrow: live-tick check"));
   if(confirm<0) legend="Signal candle is outside this picture range";
   WAPText(canvas,margin,InpPictureHeight-margin-small_size*2-14,legend,
           InpPictureWidth-margin*2,small_size,muted);
   WAPText(canvas,margin,InpPictureHeight-margin-small_size,"Captured "+
           TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+" broker · Current candle included",
           InpPictureWidth-margin*2,small_size,muted);
   return canvas.SavePNG(path);
}
#endif
