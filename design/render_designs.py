"""Generate editable SVG design review artifacts; this is not iOS app code."""
from pathlib import Path
from html import escape
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
ROOT.mkdir(exist_ok=True)
FONT = "-apple-system, BlinkMacSystemFont, 'PingFang SC', 'Hiragino Sans', sans-serif"
LIGHT = dict(bg='#F7F8FC', surface='#FFFFFF', soft='#EEF0F6', text='#191D2B', muted='#5D6578', accent='#4549E8', button='#4549E8', highlight='#ECEBFF', hi='#3338B0', line='#E3E6EF')
DARK = dict(bg='#11131B', surface='#1C2030', soft='#272D40', text='#F4F5FB', muted='#B6BDD0', accent='#A8AAFF', button='#5559E7', highlight='#303457', hi='#DFE1FF', line='#3B4255')

ICONS = {
 'book':'<path d="M12 6C8 3 4 3 2 4v15c3-1 7-1 10 2m0-15c4-3 8-3 10-2v15c-3-1-7-1-10 2V6Z"/>',
 'home':'<path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1V10Z"/>',
 'folder':'<path d="M3 7V5h7l2 3h9v12H3V7Z"/>',
 'file':'<path d="M5 3h9l5 5v13H5V3Z"/><path d="M14 3v6h5M8 13h8m-8 4h6"/>',
 'pdf':'<path d="M5 3h9l5 5v13H5V3Z"/><path d="M14 3v6h5M8 14h8m-8 4h5"/>',
 'text':'<path d="M4 5h16M12 5v15M8 20h8M4 5v3m16-3v3"/>',
 'paste':'<rect x="5" y="5" width="14" height="16" rx="2"/><rect x="8" y="2" width="8" height="5" rx="1"/><path d="M8 12h8m-8 4h6"/>',
 'plus':'<path d="M12 4v16M4 12h16"/>',
 'minus':'<path d="M4 12h16"/>',
 'back':'<path d="m14 5-7 7 7 7"/>',
 'chevron':'<path d="m9 5 7 7-7 7"/>',
 'down':'<path d="m5 9 7 7 7-7"/>',
 'close':'<path d="m6 6 12 12M6 18 18 6"/>',
 'more':'<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
 'search':'<circle cx="10" cy="10" r="6"/><path d="m15 15 6 6"/>',
 'edit':'<path d="m4 16 12-12 4 4L8 20l-5 1 1-5Zm10-10 4 4"/>',
 'bookmark':'<path d="M6 3h12v18l-6-4-6 4V3Z"/>',
 'sliders':'<path d="M4 7h16M4 17h16"/><circle cx="9" cy="7" r="3"/><circle cx="16" cy="17" r="3"/>',
 'settings':'<path d="M9 3h6l1 3 3 1 2 5-2 5-3 1-1 3H9l-1-3-3-1-2-5 2-5 3-1 1-3Z"/><circle cx="12" cy="12" r="3"/>',
 'check':'<path d="m5 12 4 4L20 5"/>',
 'shield':'<path d="m12 2 9 4v6c0 5-5 8-9 10-4-2-9-5-9-10V6l9-4Z"/><path d="m8 12 3 3 5-6"/>',
 'upload':'<path d="M4 15v6h16v-6M12 17V3m-5 5 5-5 5 5"/>',
 'voice':'<path d="M4 9v6m4-10v14m4-17v20m4-17v14m4-10v6"/>',
 'prev':'<path d="m16 5-9 7 9 7V5ZM4 5v14"/>',
 'next':'<path d="m8 5 9 7-9 7V5ZM20 5v14"/>',
 'play':'<path d="m8 4 12 8-12 8V4Z"/>',
 'pause':'<path d="M8 5v14M16 5v14"/>',
 'headphones':'<path d="M4 14v-3a8 8 0 0 1 16 0v3"/><rect x="3" y="12" width="4" height="9" rx="2"/><rect x="17" y="12" width="4" height="9" rx="2"/>',
 'lock':'<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V6a4 4 0 0 1 8 0v4m-4 4v3"/>',
 'grid':'<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
 'clock':'<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 3"/>',
 'star':'<path d="m12 2 3 6 7 1-5 5 1 8-6-4-6 4 1-8-5-5 7-1 3-6Z"/>',
 'trash':'<path d="M4 6h16M9 3h6M6 6l1 15h10l1-15M10 10v7m4-7v7"/>',
 'sun':'<circle cx="12" cy="12" r="4"/><path d="M12 1v2m0 18v2M1 12h2m18 0h2M4 4l2 2m12 12 2 2M4 20l2-2M18 6l2-2"/>',
 'info':'<circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-11v1"/>',
 'refresh':'<path d="M20 8a8 8 0 1 0 0 8M20 3v6h-6"/>',
}

class Screen:
 def __init__(self, name, dark=False):
  self.name=name; self.c=DARK if dark else LIGHT; self.p=[]
  self.rect(0,0,390,844,self.c['bg'],38)
 def rect(self,x,y,w,h,fill,r=0,stroke=None,sw=1):
  self.p.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+'/>')
 def text(self,x,y,t,size=16,color=None,weight=400,anchor='start'):
  self.p.append(f'<text x="{x}" y="{y}" fill="{color or self.c["text"]}" font-size="{size}" font-weight="{weight}" text-anchor="{anchor}" font-family="{FONT}">{escape(str(t))}</text>')
 def lines(self,x,y,lines,size=20,leading=35,color=None,weight=400):
  for i,t in enumerate(lines):
   if t: self.text(x,y+i*leading,t,size,color,weight)
 def icon(self,k,x,y,size=24,color=None):
  self.p.append(f'<g transform="translate({x},{y}) scale({size/24})" fill="none" stroke="{color or self.c["text"]}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">{ICONS[k]}</g>')
 def ib(self,k,x,y,fill=None,color=None):
  self.rect(x,y,44,44,fill or self.c['surface'],22); self.icon(k,x+10,y+10,24,color)
 def pill(self,x,y,w,t,fill=None,color=None):
  self.rect(x,y,w,28,fill or self.c['soft'],14); self.text(x+w/2,y+19,t,12,color or self.c['muted'],500,'middle')
 def button(self,x,y,w,t,primary=True):
  self.rect(x,y,w,50,self.c['button'] if primary else self.c['soft'],16); self.text(x+w/2,y+32,t,16,'#FFFFFF' if primary else self.c['text'],600,'middle')
 def header(self,title,back=True,action='more'):
  if back:self.ib('back',20,64)
  self.text(195,93,title,22,None,650,'middle')
  if action:self.ib(action,326,64)
 def nav(self,active='home'):
  self.rect(16,744,358,78,self.c['surface'],28,self.c['line'])
  for i,(k,title) in enumerate([('home','首页'),('folder','文件库'),('settings','设置')]):
   x=26+i*116
   if k==active:self.rect(x,752,106,60,self.c['highlight'],22)
   col=self.c['accent'] if k==active else self.c['muted']
   self.icon(k,x+42,759,22,col); self.text(x+53,800,title,12,col,600 if k==active else 400,'middle')
 def doc(self,y,title,sub,kind='text',progress=None):
  self.rect(24,y,342,76,self.c['surface'],18)
  self.rect(36,y+14,42,48,self.c['highlight'] if kind=='text' else '#FFF0E8',12)
  self.icon('text' if kind=='text' else 'pdf',47,y+25,21,self.c['accent'] if kind=='text' else '#A94D2B')
  self.text(91,y+30,title,16,None,600);self.text(91,y+52,sub,12,self.c['muted'])
  self.icon('chevron',338,y+27,18,self.c['muted'])
  if progress is not None:
   self.rect(91,y+63,220,3,self.c['soft'],2);self.rect(91,y+63,220*progress,3,self.c['accent'],2)
 def player(self,pdf=False,ready=True):
  self.rect(16,650,358,165,self.c['surface'],28,self.c['line'])
  self.rect(36,669,318,4,self.c['soft'],2);self.rect(36,669,104,4,self.c['accent'],2)
  self.text(36,696,'第 2 / 24 页' if pdf else '第 3 / 12 句',12,self.c['muted'])
  self.text(354,696,'00:09 / 00:33' if ready else '接入语音后可播放',12,self.c['muted'],400,'end')
  self.ib('voice',30,725,self.c['highlight'],self.c['accent']);self.text(52,791,'日语',12,self.c['muted'],500,'middle')
  self.ib('prev',90,725,self.c['surface'],self.c['text'])
  self.rect(163,715,64,64,self.c['button'] if ready else self.c['soft'],32)
  self.icon('play' if pdf else 'pause',183,735,24,'#FFFFFF' if ready else self.c['muted'])
  self.ib('next',253,725,self.c['surface'],self.c['text'])
  self.rect(314,725,44,44,self.c['soft'],22);self.text(336,753,'1.0×',12,None,600,'middle')
 def svg(self):
  return f'<svg xmlns="http://www.w3.org/2000/svg" width="390" height="844" viewBox="0 0 390 844" role="img" aria-label="{self.name}"><title>{escape(self.name)}</title>'+''.join(self.p)+'</svg>'

def home():
 s=Screen('首页')
 s.rect(24,63,34,34,s.c['button'],11);s.icon('voice',31,70,20,'#FFF');s.text(69,87,'AI Reader',20,None,650)
 s.pill(279,66,87,'本地优先', '#EAF5EF','#23684E')
 s.text(24,154,'让文字，慢慢说。',30,None,650);s.text(24,185,'从一段日语，开始今天的阅读。',14,s.c['muted'])
 s.text(24,231,'继续阅读',18,None,600)
 s.rect(24,249,342,174,s.c['surface'],24)
 s.pill(42,266,48,'TXT');s.text(101,285,'日本語 · 日常练习',12,s.c['muted'])
 s.text(42,320,'京都の朝、いつもの道',21,None,600)
 s.text(42,346,'上次读到「駅へ向かう途中…」',13,s.c['muted'])
 s.rect(42,368,165,4,s.c['soft'],2);s.rect(42,368,66,4,s.c['accent'],2)
 s.text(42,394,'文本进度 40%',12,s.c['muted'])
 s.rect(239,365,109,40,s.c['button'],13);s.text(294,391,'继续阅读',14,'#FFF',600,'middle')
 s.text(24,465,'开始新阅读',18,None,600)
 for x,k,t,sub in [(24,'edit','新建文本','自己写一段'),(142,'paste','粘贴文本','由你主动粘贴'),(260,'folder','导入文件','PDF · TXT')]:
  s.rect(x,484,106,106,s.c['surface'],20)
  s.icon(k,x+16,501,25,s.c['accent']);s.text(x+16,550,t,15,None,600);s.text(x+16,574,sub,12,s.c['muted'])
 s.text(24,630,'最近添加',18,None,600);s.text(366,630,'查看全部',13,s.c['accent'],500,'end')
 s.doc(647,'旅のことばノート','PDF · 日本語 · 今天',kind='pdf')
 s.nav();return s

ARTICLE=['今朝はいつもより少し早く','目が覚めました。窓を開けると、','涼しい風が部屋に入ってきます。','','駅へ向かう途中、小さな喫茶店で','温かいコーヒーを買いました。','','忙しい毎日でも、こうした時間を','大切にしたいと思います。']

def reader(dark=False):
 s=Screen('文本阅读器 · 接入后的播放状态示意',dark);s.header('京都の朝',action='edit')
 s.text(195,128,'日本語 · 文本阅读',12,s.c['muted'],400,'middle')
 s.pill(24,151,83,'自动跟随',s.c['highlight'],s.c['accent']);s.ib('bookmark',220,143);s.ib('search',270,143)
 s.rect(320,143,46,44,s.c['surface'],22);s.text(343,172,'Aa',17,None,500,'middle')
 s.lines(24,236,ARTICLE[:3],20,36)
 s.rect(20,345,350,72,s.c['highlight'],12)
 s.lines(24,370,ARTICLE[4:6],20,36,s.c['hi'],500)
 s.lines(24,464,ARTICLE[7:],20,36)
 s.text(24,563,'长按选择文字，或添加书签。',13,s.c['muted'])
 s.player();return s

def speed():
 s=reader();s.name='语速调整 · 底部面板'
 s.rect(0,0,390,844,'#10142666',38)
 s.rect(0,335,390,509,s.c['surface'],32)
 s.rect(169,346,52,5,'#C7CCD8',3)
 s.text(24,394,'语速',22,None,650);s.ib('close',326,366,s.c['soft'])
 s.text(24,424,'找到适合自己的阅读节奏',14,s.c['muted'])
 s.ib('minus',36,459,s.c['soft']);s.text(195,501,'1.0×',52,None,650,'middle');s.ib('plus',310,459,s.c['soft'])
 s.rect(42,537,306,6,s.c['soft'],3);s.rect(42,537,102,6,s.c['accent'],3);s.rect(132,528,24,24,s.c['accent'],12)
 s.text(42,571,'0.5×',12,s.c['muted']);s.text(348,571,'2.0×',12,s.c['muted'],400,'end')
 for i,t in enumerate(['0.75×','1.0×','1.25×','1.5×','1.75×','2.0×']):
  x=24+(i%3)*118;y=592+(i//3)*52;sel=i==1
  s.rect(x,y,106,44,s.c['highlight'] if sel else s.c['soft'],14);s.text(x+53,y+28,t,15,s.c['accent'] if sel else s.c['text'],600 if sel else 500,'middle')
 s.text(24,721,'设为默认语速',15,None,500);s.rect(314,700,52,32,s.c['soft'],16);s.rect(317,703,26,26,'#FFF',13)
 s.text(24,759,'未接入引擎时仅保存偏好，接入后生效。',12,s.c['muted'])
 s.text(24,783,'实际可调范围以本地语音引擎为准。',12,s.c['muted']);return s

def pdf():
 s=Screen('PDF 阅读器');s.header('旅のことばノート',action='more')
 s.rect(24,126,342,44,s.c['soft'],14);s.rect(28,130,165,36,s.c['surface'],11);s.text(110,154,'原文',14,None,600,'middle');s.text(280,154,'文本',14,s.c['muted'],500,'middle')
 s.rect(24,190,342,408,s.c['surface'],5,s.c['line'])
 s.rect(24,190,11,408,'#DADCF8',0)
 s.text(52,227,'JAPANESE NOTES',10,s.c['muted'],500)
 s.text(52,283,'旅のことば',27,None,600);s.text(52,322,'小さな旅、日本語で。',17,s.c['muted'])
 # Deliberately original vector document artwork.
 s.rect(52,347,286,107,'#F1F0FC',14)
 s.p.append('<path d="M52 432 Q110 340 169 412 T338 391V454H52Z" fill="#D1D4F5"/><path d="M52 447 Q140 382 225 425 T338 419V454H52Z" fill="#989FDF"/>')
 s.text(52,488,'01  駅で使う表現',17,None,600)
 s.lines(52,519,['次の電車は何時に出発しますか。','京都までの切符を一枚ください。','この電車は大阪に止まりますか。'],13,25,s.c['muted'])
 s.icon('grid',24,615,19,s.c['muted']);s.text(195,630,'2 / 24',13,s.c['muted'],500,'middle');s.text(366,630,'目录',13,s.c['accent'],500,'end')
 s.player(pdf=True);return s

def library():
 s=Screen('文件库');s.text(24,94,'文件库',22,None,650);s.ib('plus',322,64,s.c['button'],'#FFF')
 s.rect(24,127,342,48,s.c['surface'],14);s.icon('search',39,140,21,s.c['muted']);s.text(73,158,'搜索标题或正文',15,s.c['muted'])
 for x,w,t,sel in [(24,68,'全部',True),(100,68,'文本',False),(176,68,'PDF',False),(252,78,'收藏',False)]:s.pill(x,194,w,t,s.c['highlight'] if sel else s.c['surface'],s.c['accent'] if sel else s.c['muted'])
 s.text(24,267,'文件夹',17,None,600);s.text(366,267,'管理',13,s.c['accent'],500,'end')
 for x,t,n in [(24,'日语学习','8 篇资料'),(201,'旅行笔记','4 篇资料')]:
  s.rect(x,285,165,103,s.c['surface'],18);s.icon('folder',x+16,300,25,s.c['accent']);s.text(x+16,347,t,16,None,600);s.text(x+16,370,n,12,s.c['muted'])
 s.text(24,429,'全部资料',17,None,600);s.text(366,429,'最近打开',12,s.c['muted'],400,'end')
 s.doc(448,'京都の朝、いつもの道','TXT · 日本語 · 阅读到 40%',progress=.4)
 s.doc(536,'旅のことばノート','PDF · 24 页 · 日本語',kind='pdf')
 s.doc(624,'週末の小さな計画','文本 · 日本語 · 昨天')
 s.nav('folder');return s

def importer():
 s=library();s.name='本地文件导入确认';s.rect(0,0,390,844,'#10142666',38)
 s.rect(0,248,390,596,s.c['surface'],32);s.rect(169,259,52,5,'#C7CCD8',3)
 s.text(24,307,'导入到本机',22,None,650);s.ib('close',326,279,s.c['soft'])
 s.text(24,340,'文件只会复制到 App 的本地资料库。',14,s.c['muted'])
 s.rect(24,365,342,90,s.c['bg'],18);s.rect(40,381,44,58,'#FFF0E8',12);s.icon('pdf',50,397,24,'#A94D2B')
 s.text(98,401,'旅のことばノート.pdf',16,None,600);s.text(98,430,'PDF · 24 页 · 2.4 MB（示例）',12,s.c['muted'])
 s.text(24,494,'朗读语言',14,s.c['muted']);s.text(366,494,'日本語  ›',15,None,500,'end')
 s.rect(24,515,342,1,s.c['line'])
 s.text(24,551,'保存到',14,s.c['muted']);s.text(366,551,'日语学习  ›',15,None,500,'end')
 s.rect(24,572,342,1,s.c['line'])
 s.rect(24,596,342,70,'#EAF5EF',16);s.icon('shield',40,614,21,'#23684E');s.text(72,622,'不上传文件或正文',14,'#23684E',600);s.text(72,645,'本机文件导入后可离线打开。',12,'#23684E')
 s.button(24,698,342,'确认导入')
 s.text(195,779,'支持 PDF、TXT、MD',12,s.c['muted'],400,'middle');return s

def editor():
 s=Screen('文本编辑器');s.text(24,93,'取消',16,s.c['muted']);s.text(195,93,'编辑文本',22,None,650,'middle');s.text(366,93,'保存',16,s.c['accent'],600,'end')
 s.text(24,144,'标题',13,s.c['muted']);s.rect(24,158,342,52,s.c['surface'],14);s.text(40,191,'京都の朝、いつもの道',17,None,600)
 s.pill(24,228,105,'日本語 · ja-JP');s.text(366,248,'286 字（示例）',12,s.c['muted'],400,'end')
 s.text(24,292,'正文',13,s.c['muted']);s.text(366,292,'粘贴',14,s.c['accent'],500,'end')
 s.rect(24,307,342,350,s.c['surface'],18)
 s.lines(40,345,['今朝はいつもより少し早く','目が覚めました。窓を開けると、','涼しい風が部屋に入ってきます。','','駅へ向かう途中、小さな喫茶店で','温かいコーヒーを買いました。'],18,32)
 s.rect(40,572,2,26,s.c['accent'],1)
 s.icon('check',24,679,17,'#23684E');s.text(50,693,'已保存到本机 · 状态示意',12,s.c['muted'])
 s.rect(24,724,342,72,s.c['highlight'],18);s.icon('book',41,747,24,s.c['accent']);s.text(83,750,'保存后进入阅读器',15,s.c['hi'],600);s.text(83,775,'编辑内容保留在本机，不发送到服务器。',12,s.c['hi']);return s

def voice():
 s=Screen('语音与语言 · 未接入状态');s.header('语音与语言',action=None)
 s.rect(24,134,342,157,s.c['surface'],24);s.rect(44,155,44,44,s.c['highlight'],14);s.icon('voice',54,165,24,s.c['accent'])
 s.text(44,232,'朗读，在设备上完成。',21,None,600);s.text(44,264,'无需外部 TTS App 或远程语音服务。',13,s.c['muted'])
 s.text(24,333,'首发语言',17,None,600)
 s.rect(24,351,342,87,s.c['surface'],18);s.text(42,383,'日本語',18,None,600);s.text(42,412,'ja-JP · 日语端侧引擎',13,s.c['muted']);s.pill(282,377,66,'待接入','#FFF4DC','#855308')
 s.rect(24,460,342,124,'#FFF4DC',18);s.icon('info',40,479,22,'#855308');s.text(73,495,'语音引擎尚未接入',15,'#855308',600);s.lines(40,526,['当前可阅读、编辑和管理本地文本。','音色、模型体积和兼容性将在接入后确定。'],12,25,'#855308')
 s.text(24,628,'后续语言扩展',17,None,600);s.text(24,658,'每种语言使用独立的本地资源与发音策略。',13,s.c['muted'])
 s.rect(24,717,342,50,s.c['soft'],16);s.icon('lock',87,730,20,s.c['muted']);s.text(217,748,'试听 · 接入后可用',15,s.c['muted'],500,'middle')
 s.text(195,796,'此页没有自动下载或联网合成。',12,s.c['muted'],400,'middle');return s

def settings():
 s=Screen('设置');s.text(24,94,'设置',22,None,650)
 s.rect(24,130,342,80,s.c['surface'],20);s.icon('shield',43,154,27,'#23684E');s.text(87,162,'内容留在你的设备',17,None,600);s.text(87,186,'本地资料库 · 无需登录',13,s.c['muted'])
 s.text(24,253,'阅读与语音',17,None,600)
 rows=[('voice','语音与语言','待接入'),('sliders','默认语速','1.0×'),('text','阅读显示','字号 · 行距'),('sun','外观','跟随系统')]
 for i,(k,t,v) in enumerate(rows):
  y=271+i*62;s.rect(24,y,342,61,s.c['surface'],12 if i in (0,3) else 0);s.icon(k,41,y+20,22,s.c['muted']);s.text(78,y+37,t,15,None,500);s.text(335,y+37,v,12,s.c['muted'],400,'end');s.icon('chevron',342,y+25,14,s.c['muted'])
 s.text(24,565,'本地数据',17,None,600)
 for i,(k,t,v) in enumerate([('folder','存储与缓存','28.4 MB · 示例'),('trash','最近删除','30 天内可恢复')]):
  y=584+i*62;s.rect(24,y,342,61,s.c['surface'],12);s.icon(k,41,y+20,22,s.c['muted']);s.text(78,y+37,t,15,None,500);s.text(335,y+37,v,12,s.c['muted'],400,'end');s.icon('chevron',342,y+25,14,s.c['muted'])
 s.nav('settings');return s

def empty():
 s=Screen('文件库 · 首次使用空态');s.text(24,94,'文件库',22,None,650);s.ib('plus',322,64,s.c['button'],'#FFF')
 s.rect(24,127,342,48,s.c['surface'],14);s.icon('search',39,140,21,s.c['muted']);s.text(73,158,'搜索标题或正文',15,s.c['muted'])
 s.rect(143,274,104,116,s.c['highlight'],28);s.icon('book',167,306,56,s.c['accent'])
 s.text(195,443,'从第一段日语开始',24,None,600,'middle')
 s.lines(195,477,['写下几句话，或导入一份文档。','你的资料会保存在这台设备上。'],14,27,s.c['muted'])
 # Center the preceding explanatory lines.
 s.p[-2]=s.p[-2].replace('text-anchor="start"','text-anchor="middle"');s.p[-1]=s.p[-1].replace('text-anchor="start"','text-anchor="middle"')
 s.button(56,555,278,'导入文件');s.button(56,619,278,'新建文本',False)
 s.nav('folder');return s

SCREENS=[('01-home',home()),('02-text-reader',reader()),('03-speed',speed()),('04-pdf-reader',pdf()),('05-library',library()),('06-import',importer()),('07-editor',editor()),('08-voices',voice()),('09-settings',settings()),('10-empty',empty()),('11-reader-dark',reader(True))]

for name,screen in SCREENS:
 (ROOT/(name+'.svg')).write_text(screen.svg())

def board(filename,title,subtitle,items,cols):
 gap=40;margin=48;top=184;rowgap=100
 rows=(len(items)+cols-1)//cols
 width=margin*2+cols*390+(cols-1)*gap
 height=top+rows*844+(rows-1)*rowgap+80
 pieces=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-label="{escape(title)}"><title>{escape(title)}</title>',f'<rect width="{width}" height="{height}" fill="#ECEEF5"/>',f'<text x="48" y="64" font-size="32" font-weight="650" fill="#191D2B" font-family="{FONT}">{escape(title)}</text>',f'<text x="48" y="103" font-size="16" fill="#5D6578" font-family="{FONT}">{escape(subtitle)}</text>']
 for i,(slug,label,desc) in enumerate(items):
  x=margin+(i%cols)*(390+gap);y=top+(i//cols)*(844+rowgap)
  pieces.append(f'<text x="{x}" y="{y-31}" font-size="17" fill="#191D2B" font-weight="600" font-family="{FONT}">{escape(label)}</text>')
  screen=dict(SCREENS)[slug]
  pieces.append(f'<g transform="translate({x},{y})">'+''.join(screen.p)+f'<rect width="390" height="844" rx="38" fill="none" stroke="#C7CCDB" stroke-width="1"/></g>')
  pieces.append(f'<text x="{x}" y="{y+869}" font-size="12" fill="#5D6578" font-family="{FONT}">{escape(desc)}</text>')
 pieces.append(f'<text x="48" y="{height-22}" font-size="12" fill="#5D6578" font-family="{FONT}">AI Reader · 2026.10.23 · 静态设计评审稿；样例数据与播放状态不代表功能已实现。</text></svg>')
 (ROOT/filename).write_text(''.join(pieces))

board('overview.svg','AI Reader / 让阅读留在本机','iOS 本地日语朗读 · 白底、安静的蓝紫色、内容优先 · 四张核心页面',[
 ('01-home','01 / 首页','继续阅读 · 新建与导入 · 最近资料'),
 ('02-text-reader','02 / 文本阅读','接入后播放态示意 · 句级跟随 · 悬浮播放器'),
 ('03-speed','03 / 语速调整','底部面板 · 精细加减 · 默认偏好'),
 ('04-pdf-reader','04 / PDF 阅读','原文 / 文本 · 页码与目录 · 共享播放器')],4)
board('supporting.svg','从导入到阅读，一条完整的本地路径。','辅助页面覆盖文件管理、文字创作、离线资源和关键空状态。',[
 ('05-library','05 / 文件库','搜索 · 文件夹 · 类型筛选 · 资料管理'),
 ('06-import','06 / 导入确认','系统选取后，本地复制 · 语言与目标文件夹'),
 ('07-editor','07 / 文本编辑','可见表单标签 · 日文正文 · 草稿与保存状态'),
 ('08-voices','08 / 语音与语言','未接入状态 · 语言能力 · 禁用试听'),
 ('09-settings','09 / 设置','阅读偏好 · 存储管理 · 最近删除'),
 ('10-empty','10 / 首次使用','清晰解释 · 导入与新建 · 可恢复的起点')],3)
board('theme-comparison.svg','阅读专注，浅色与深色一致。','使用独立语义色彩，维持正文与控制区的阅读层级。',[
 ('02-text-reader','浅色阅读','当前句淡紫底；其余正文保持清晰'),
 ('11-reader-dark','深色阅读','独立表面与文字色；PDF 不自动反色')],2)

def luminance(h):
 v=[int(h[i:i+2],16)/255 for i in (1,3,5)]
 v=[x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4 for x in v]
 return sum(x*w for x,w in zip(v,[.2126,.7152,.0722]))
checks=[]
for mode,palette in [('light',LIGHT),('dark',DARK)]:
 for fg,bg in [('text','bg'),('muted','bg'),('text','surface'),('muted','surface'),('accent','surface'),('hi','highlight')]:
  a,b=sorted([luminance(palette[fg]),luminance(palette[bg])]);ratio=(b+.05)/(a+.05)
  checks.append(dict(theme=mode,foreground=fg,background=bg,ratio=round(ratio,2),passes=ratio>=4.5))
 a,b=sorted([luminance('#FFFFFF'),luminance(palette['button'])]);ratio=(b+.05)/(a+.05)
 checks.append(dict(theme=mode,foreground='onButtonPrimary',background='button',ratio=round(ratio,2),passes=ratio>=4.5))
for file in ROOT.glob('*.svg'): ET.parse(file)
assert all(x['passes'] for x in checks),checks
(ROOT/'contrast-check.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'screens':len(SCREENS),'svg_files':len(list(ROOT.glob('*.svg'))),'contrast_pairs':len(checks),'all_pass':True},ensure_ascii=False))
