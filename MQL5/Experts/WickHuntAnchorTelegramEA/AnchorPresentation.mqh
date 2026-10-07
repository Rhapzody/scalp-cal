#ifndef WHA_ALERT_PRESENTATION
#define WHA_ALERT_PRESENTATION
// Presentation only. The prefix stays inside the schema-1 message field;
// the sender removes it before Telegram and escapes legacy plain records.
#define WAF_HTML_PREFIX "@WHA_HTML_1\n"
string WAFEscape(const string text)
{
   string out=text;
   StringReplace(out,"&","&amp;"); StringReplace(out,"<","&lt;");
   StringReplace(out,">","&gt;"); StringReplace(out,"\"","&quot;");
   return out;
}
string WAFShortID(const string id) { return StringSubstr(id,0,8); }
bool WAFIsHTML(const string text) { return StringFind(text,WAF_HTML_PREFIX)==0; }
string WAFMessageHTML(const string text)
{ return WAFIsHTML(text) ? StringSubstr(text,StringLen(WAF_HTML_PREFIX)) : WAFEscape(text); }
string WAFPrice(const double price,const int digits)
{
   string raw=DoubleToString(price,digits);
   int dot=StringFind(raw,"."),end=dot<0 ? StringLen(raw) : dot;
   for(int at=end-3;at>0;at-=3) raw=StringSubstr(raw,0,at)+","+StringSubstr(raw,at);
   return raw;
}
string WAFLine(const string text,const int line)
{
   int start=0;
   for(int i=0;i<line;i++)
   { int next=StringFind(text,"\n",start); if(next<0) return ""; start=next+1; }
   int end=StringFind(text,"\n",start);
   return end<0 ? StringSubstr(text,start) : StringSubstr(text,start,end-start);
}
string WAFAlbumCaption(const WATRecord &e,const string id)
{
   string header="<b>WickHunt Anchor · "+(e.direction==1 ? "BUY" : "SELL")+"</b>",pair="";
   if(WAFIsHTML(e.message))
   {
      string text=WAFMessageHTML(e.message);
      header=WAFLine(text,0); pair=WAFLine(text,1);
      StringReplace(pair,"WickHunt Anchor · ",""); StringReplace(pair," → "," / ");
   }
   // An old pending record remains readable without changing its stored body.
   else header=WAFEscape(WAFLine(e.message,0));
   return "📷 "+header+(pair!="" ? "\n"+pair : "")+"\n"+
          TimeToString((datetime)e.time,TIME_DATE|TIME_MINUTES)+" · เวลาโบรกเกอร์\n"+
          "<code>#"+WAFShortID(id)+"</code>";
}
#endif
