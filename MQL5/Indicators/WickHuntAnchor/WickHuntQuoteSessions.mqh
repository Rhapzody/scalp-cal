#ifndef WICK_HUNT_QUOTE_SESSIONS
#define WICK_HUNT_QUOTE_SESSIONS

// Broker-wall-clock weekly QUOTE sessions, not order/trade permission hours.
// The end may exceed one day for overnight sessions. End is exclusive.
struct WHAQuoteSession
{
   int weekday;
   long begin,end;
};
WHAQuoteSession g_wha_quote_sessions[];
bool g_wha_quote_ready=false;
long g_wha_quote_checked=0;

bool WHALoadQuoteSessions(const string symbol,WHAQuoteSession &sessions[])
{
   ArrayResize(sessions,0);
   if(!SymbolIsSynchronized(symbol)) return false;
   for(int day=0;day<7;day++)
   {
      uint index=0;
      for(;index<64;index++)
      {
         datetime begin=0,end=0;
         if(!SymbolInfoSessionQuote(symbol,(ENUM_DAY_OF_WEEK)day,index,begin,end)) break;
         if((long)begin<0 || (long)end<0) return false;
         // Ignore the date part. A midnight end, same start/end (24h),
         // or an earlier end crosses midnight; preserve its full duration.
         long start=(long)begin%86400,finish=(long)end%86400;
         if(finish<=start) finish+=86400;
         int n=ArraySize(sessions);
         if(ArrayResize(sessions,n+1)!=n+1) return false;
         sessions[n].weekday=day; sessions[n].begin=start; sessions[n].end=finish;
      }
      // Never call a truncated schedule complete.
      if(index==64) return false;
   }
   return ArraySize(sessions)>0;
}

bool WHARefreshQuoteSessions(const string symbol)
{
   long now=(long)TimeLocal();
   if(g_wha_quote_checked>0 && now>=g_wha_quote_checked && now-g_wha_quote_checked<60) return false;
   g_wha_quote_checked=now;
   WHAQuoteSession loaded[];
   // Retain a previously verified schedule during a transient metadata failure.
   // Without any verified schedule, only uninterrupted bar times are allowed.
   if(!WHALoadQuoteSessions(symbol,loaded)) return false;
   int n=ArraySize(loaded);
   bool changed=!g_wha_quote_ready || n!=ArraySize(g_wha_quote_sessions);
   if(!changed)
      for(int i=0;i<n;i++)
         if(loaded[i].weekday!=g_wha_quote_sessions[i].weekday ||
            loaded[i].begin!=g_wha_quote_sessions[i].begin || loaded[i].end!=g_wha_quote_sessions[i].end)
         { changed=true; break; }
   if(!changed) return false;
   if(ArrayResize(g_wha_quote_sessions,n)!=n) return false;
   for(int i=0;i<n;i++) g_wha_quote_sessions[i]=loaded[i];
   g_wha_quote_ready=true;
   return true;
}

// A missing [from,to) is allowed ONLY if no scheduled quote interval overlaps.
// Include the preceding calendar day so overnight sessions cannot be missed.
// Called only for gaps within a single main candle (main TF <= 1 day).
bool WHAClosedQuoteGap(const long from,const long to)
{
   if(from<=0 || to<from || to-from>86400) return false;
   if(to==from) return true;
   if(!g_wha_quote_ready) return false;
   long midnight=from-from%86400;
   for(long origin=midnight-86400;origin<to;origin+=86400)
   {
      MqlDateTime date;
      if(!TimeToStruct((datetime)origin,date)) return false;
      for(int i=0;i<ArraySize(g_wha_quote_sessions);i++)
      {
         WHAQuoteSession session=g_wha_quote_sessions[i];
         if(session.weekday!=date.day_of_week) continue;
         long begin=origin+session.begin,end=origin+session.end;
         if(begin<to && end>from) return false;
      }
   }
   return true;
}
#endif
