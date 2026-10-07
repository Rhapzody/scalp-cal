"""Extract the indicator runtime for the alert EA; never edit trading conditions here."""
from pathlib import Path
import hashlib, re
root=Path(__file__).resolve().parents[1]
p=root/'MQL5/Indicators/WickHuntAnchor/WickHuntAnchor.mq5'
s=p.read_text(encoding='utf-8-sig')
version=re.search(r'#property\s+version\s+"([^"]+)"',s).group(1)
inputs=s[s.index('input group'):s.index('int OnInit()')]
inputs=inputs.replace('double BuyBuffer[],SellBuffer[],TimeBuffer[],DirectionBuffer[],TipBuffer[];\ndouble AnchorTimeBuffer[],PatternBuffer[],HeadWickBuffer[],SourceBuffer[];\n','')
inputs=inputs.replace('"WickHuntAnchor | "','"WickHuntAnchor EA | "')
body=s[s.index('bool LoadHistory()'):s.index('void MapBuffers()')]
u=s[s.index('void UpdateIndicator()'):s.index('void OnTimer()')]
u=u.replace('void UpdateIndicator()', 'bool UpdateEngine()').replace('return;', 'return false;')
u=u[:u.index('   if(!RenderEvents())')]+ '   return true;\n}\n'
# Same inputs, sweep, first collision, replay, cancellation and live observation.
out=f'// Generated from WickHuntAnchor {version}. Regenerate with scripts/sync-wick-hunt-anchor-runtime.py\n'
out+='// Source SHA256: '+hashlib.sha256(p.read_bytes()).hexdigest()+'\n'
out+='#ifndef WHA_ALERT_RUNTIME\n#define WHA_ALERT_RUNTIME\n#include "../../Indicators/WickHuntAnchor/WickHuntAnchorCore.mqh"\n#include "../../Indicators/WickHuntAnchor/WickHuntQuoteSessions.mqh"\n'+inputs+body+u+'#endif\n'
(root/'MQL5/Experts/WickHuntAnchorTelegramEA/AnchorRuntime.mqh').write_text(out,encoding='utf-8-sig')
validation=s[s.index('   g_hunt_tf='):s.index('   SetIndexBuffer')]
(root/'MQL5/Experts/WickHuntAnchorTelegramEA/AnchorValidation.mqh').write_text(f'// Generated validation from indicator {version}; included inside OnInit.\n'+validation,encoding='utf-8-sig')
print(f'Generated EA runtime from indicator {version} without changing detection conditions')
