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
bool WAPRender(const WATRecord &e,const ENUM_TIMEFRAMES tf,const string path,const int requested)
{
   MqlRates rates[]; ArraySetAsSeries(rates,false);
   if(!SeriesInfoInteger(_Symbol,tf,SERIES_SYNCHRONIZED)) return false;
   int n=CopyRates(_Symbol,tf,0,requested,rates);
   if(n<2) return false;
   CWAPCanvas canvas;
   if(!canvas.Create("WHA_memory_"+(string)GetMicrosecondCount(),InpPictureWidth,InpPictureHeight)) return false;
   canvas.Erase(ColorToARGB(clrBlack));
   if(!canvas.FontSet("Arial",-140)) return false;
   int left=45,top=100,width=InpPictureWidth-155,height=InpPictureHeight-160;
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
   double step=(double)width/(n+5);
   int body=(int)MathMax(1,MathMin(12,step*0.32));
   uint gray=ColorToARGB(clrDimGray),silver=ColorToARGB(clrSilver),white=ColorToARGB(clrWhite),gold=ColorToARGB(clrGold);
   for(int k=0;k<=5;k++)
   {
      double price=low+range*k/5.0; int y=WAPY(price,low,range,top,height);
      canvas.LineHorizontal(left,left+width,y,gray);
      canvas.TextOut(left+width+8,y-8,DoubleToString(price,_Digits),silver);
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
      if(i%((int)MathMax(1,n/6))==0)
         canvas.TextOut(x-18,top+height+10,TimeToString(b.time,TIME_DATE|TIME_MINUTES),silver);
   }
   int tip_y=WAPY(e.tip,low,range,top,height);
   int from=anchor>=0 ? left+(int)MathRound((anchor+0.5)*step) : left;
   int to=signal_x>=0 ? signal_x : left+width;
   if(InpShowAnchorLinks) canvas.LineHorizontal(from,to,tip_y,ColorToARGB(InpAnchorColor));
   canvas.TextOut(left,75,"Wick tip at signal "+DoubleToString(e.tip,_Digits)+" | Anchor "+TimeToString((datetime)e.anchor,TIME_DATE|TIME_MINUTES),silver);
   if(anchor>=0 && tf==g_hunt_tf)
   {
      int x=left+(int)MathRound((anchor+0.5)*step);
      canvas.Rectangle(x-body-3,WAPY(rates[anchor].high,low,range,top,height)-3,
                       x+body+3,WAPY(rates[anchor].low,low,range,top,height)+3,gold);
   }
   if(confirm>=0)
   {
      int x=left+(int)MathRound((confirm+0.5)*step);
      canvas.LineVertical(x,top,top+height,gold);
      int y=WAPY(e.direction==1 ? rates[confirm].low : rates[confirm].high,low,range,top,height);
      int sign=e.direction==1 ? 1 : -1;
      y+=sign*18;
      uint ink=ColorToARGB(e.direction==1 ? InpBuyColor : InpSellColor);
      canvas.FillTriangle(x,y-sign*6,x-6,y+sign*5,x+6,y+sign*5,ink);
      canvas.LineVertical(x,y+sign*5,y+sign*14,ink);
   }
   canvas.TextOut(15,15,"WickHuntAnchor | "+_Symbol+" "+TFText(tf)+" | "+(e.direction==1 ? "BUY" : "SELL")+" | "+PatternText(e.pattern),white);
   canvas.TextOut(15,42,"Signal (broker) "+TimeToString((datetime)e.time,TIME_DATE|TIME_SECONDS)+
                  " | Image data captured "+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),silver);
   canvas.TextOut(15,InpPictureHeight-25,"Gold line = confirmation candle | Gold box = main-TF anchor | Link frozen at signal wick | Current candle included",silver);
   return canvas.SavePNG(path);
}
#endif
