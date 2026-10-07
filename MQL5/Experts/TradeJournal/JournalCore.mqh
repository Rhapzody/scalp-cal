#ifndef TRADE_JOURNAL_CORE
#define TRADE_JOURNAL_CORE

// All fields quoted, single physical line per record; free text cannot become an Excel formula.
string TJCell(string value,const bool free_text=false)
{
   if(free_text && StringLen(value)>0)
   {
      int first=StringGetCharacter(value,0);
      if(first=='=' || first=='+' || first=='-' || first=='@' || first=='\t' || first=='\r' || first=='\n') value="'"+value;
   }
   StringReplace(value,"\r","\\r");
   StringReplace(value,"\n","\\n");
   StringReplace(value,"\"","\"\"");
   return "\""+value+"\"";
}
void TJAdd(string &row,const string value,const bool free_text=false)
{
   if(row!="") row+=",";
   row+=TJCell(value,free_text);
}

// Strict parser for our own quoted, single-line CSV. Reject torn/foreign records.
bool TJParse(const string line,string &fields[])
{
   ArrayResize(fields,0);
   int at=0,n=StringLen(line);
   if(n==0) return false;
   while(at<n)
   {
      if(StringGetCharacter(line,at)!='"') return false;
      at++;
      string value="";
      bool closed=false;
      while(at<n)
      {
         if(StringGetCharacter(line,at)=='"')
         {
            if(at+1<n && StringGetCharacter(line,at+1)=='"') { value+="\""; at+=2; }
            else { at++; closed=true; break; }
         }
         else { value+=StringSubstr(line,at,1); at++; }
      }
      if(!closed) return false;
      int count=ArraySize(fields);
      if(ArrayResize(fields,count+1)!=count+1) return false;
      fields[count]=value;
      if(at==n) return true;
      if(StringGetCharacter(line,at)!=',' || at+1==n) return false;
      at++;
   }
   return false;
}

bool TJUnsigned(const string text,ulong &value)
{
   value=0;
   if(StringLen(text)==0) return false;
   for(int i=0;i<StringLen(text);i++)
   {
      int digit=StringGetCharacter(text,i)-'0';
      if(digit<0 || digit>9 || value>1844674407370955161 ||
         (value==1844674407370955161 && digit>5)) return false;
      value=value*10+(ulong)digit;
   }
   return true;
}

string TJId(const ulong value) { return StringFormat("%I64u",value); }
string TJNum(const double value) { return DoubleToString(value,10); }

// Sorted ticket index. Only commit state AFTER a successful append + flush.
struct TJState
{
   ulong ticket;
   int revision;
   string payload;
   bool deleted;
};
int TJLower(const TJState &states[],const ulong ticket)
{
   int lo=0,hi=ArraySize(states);
   while(lo<hi)
   {
      int mid=lo+(hi-lo)/2;
      if(states[mid].ticket<ticket) lo=mid+1;
      else hi=mid;
   }
   return lo;
}
int TJRevision(const TJState &states[],const ulong ticket,const string payload,const bool deleted)
{
   int at=TJLower(states,ticket);
   if(at==ArraySize(states) || states[at].ticket!=ticket) return 1;
   if(states[at].payload==payload && states[at].deleted==deleted) return 0;
   return states[at].revision+1;
}
bool TJCommit(TJState &states[],const ulong ticket,const string payload,const bool deleted,const int revision)
{
   int at=TJLower(states,ticket),n=ArraySize(states);
   if(at==n || states[at].ticket!=ticket)
   {
      if(ArrayResize(states,n+1,1024)!=n+1) return false;
      for(int i=n;i>at;i--) states[i]=states[i-1];
   }
   states[at].ticket=ticket; states[at].payload=payload;
   states[at].deleted=deleted; states[at].revision=revision;
   return true;
}

// File-system identity is reversible UTF-16 hex: no server-name sanitization collisions.
string TJServerKey(const string server)
{
   string key="";
   for(int i=0;i<StringLen(server);i++) key+=StringFormat("%04X",StringGetCharacter(server,i));
   return key;
}
#endif
