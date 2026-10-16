"""Render a labelled dashboard design reference, not a Windows screenshot.

Developer-only: Python, Pillow and PyMuPDF. Data comes from usage.js via
export_design_sample.cjs. Coordinates/palette mirror ui.xaml and DesignPreview.
Usage: python src/render_design.py sample.json image.png
"""
import io, json, math, sys
import fitz
from PIL import Image, ImageDraw, ImageFont

S=2
W,H=1380,940
im=Image.new('RGB',(W*S,H*S),'#F5F7FA')
draw=ImageDraw.Draw(im)
data=json.load(open(sys.argv[1],encoding='utf8'))
cjk=fitz.Font('korea').buffer
fonts={}
INK='#25324A'; MUTED='#7C8AA1'; BLUE='#4F76B6'; LINE='#E4EAF2'

def font(size,bold=False,ko=False):
    key=(size,bold,ko)
    if key not in fonts:
        src=io.BytesIO(cjk) if ko else '/usr/share/fonts/truetype/dejavu/DejaVuSans'+('-Bold' if bold else '')+'.ttf'
        fonts[key]=ImageFont.truetype(src,round(size*S))
    return fonts[key]

def chunks(s):
    last=None; buf=''
    for ch in str(s):
        ko=ord(ch)>0x2fff
        if last is not None and last!=ko:
            yield buf,last;buf=''
        buf+=ch;last=ko
    if buf:yield buf,last

def width(s,size=12,bold=False):
    return sum(draw.textlength(t,font=font(size,bold,ko)) for t,ko in chunks(s))/S

def text(x,y,s,size=12,color=INK,bold=False,align='left'):
    if align=='right': x-=width(s,size,bold)
    if align=='center': x-=width(s,size,bold)/2
    for t,ko in chunks(s):
        f=font(size,bold,ko)
        draw.text((round(x*S),round(y*S)),t,font=f,fill=color,anchor='lt',stroke_width=1 if ko and bold else 0)
        x+=draw.textlength(t,font=f)/S

def box(x,y,w,h,fill='white',outline=LINE,r=14):
    draw.rounded_rectangle((x*S,y*S,(x+w)*S,(y+h)*S),radius=r*S,fill=fill,outline=outline,width=S)

def line(x,y,x2,y2,color=LINE):
    draw.line((x*S,y*S,x2*S,y2*S),fill=color,width=S)

def button(x,y,w,label,primary=False,select=False):
    box(x,y,w,36,BLUE if primary else 'white',BLUE if primary else LINE,8)
    text(x+12,y+11,label,12,'white' if primary else '#405470',primary)
    if select:
        draw.line(((x+w-21)*S,(y+15)*S,(x+w-17)*S,(y+19)*S,(x+w-13)*S,(y+15)*S),fill=MUTED,width=S)

def n(v):return f'{v:,}'
def usd(v):return f'${v:.4f}'

# Sidebar and header from native ui.xaml.
draw.rectangle((0,0,188*S,H*S),fill='white');line(188,0,188,H)
box(20,28,34,34,BLUE,BLUE,10);text(37,35,'S',20,'white',True,'center')
text(64,28,'Seed Lab',18,bold=True);text(64,52,'PRESET STUDIO',8,'#93A0B5')
text(32,103,'WORKSPACE',9,'#A1ADC0',True)
box(20,126,148,42,'#EAF1FC','#EAF1FC',8)
text(34,140,'사용량 대시보드',12,'#31598F',True)
text(34,190,'프리셋 생성',12,MUTED)
text(34,240,'생성 결과',12,MUTED)
text(26,850,'YOUR STYLE.',9,'#99A6BA');text(26,866,'MORE POSSIBILITIES.',9,'#99A6BA')
text(26,906,'Desktop · v1.1',10,'#99A6BA')
text(216,28,'사용량 대시보드',26,bold=True)
text(216,70,'토큰과 이용 추세를 한눈에 확인하세요.',12,MUTED)
box(1054,29,298,30,'#EAF2EE','#EAF2EE',15)
text(1068,38,'● 디자인 렌더 · 샘플 데이터',11,'#648B78')
button(216,116,110,'최근 7일',select=True);button(334,116,166,'전체 모델',select=True)
button(1073,116,88,'새로고침');button(1169,116,85,'호출 CSV');button(1262,116,90,'일별 CSV')

t=data['totals']
labels=['총 사용 토큰','API 호출','프리셋 생성 작업','예상 API 비용 · USD']
values=[n(t['totalTokens']),n(t['calls']),n(t['runs']),usd(t['estimatedUSD'])]
change=data['changePercent']
metas=[f'전기간 대비 {change:+}%' if change is not None else '확인된 응답의 입력 + 출력',f"확인된 응답 {t['knownCalls']}건 · 미확인 {t['unknownCalls']}건",f"생성된 프리셋 {n(t['generatedPresets'])}개",'기록 시점의 요금표 기준']
cw=275
for i in range(4):
    x=216+i*(cw+12)
    box(x,168,cw,124)
    text(x+20,189,labels[i],11,MUTED)
    text(x+20,214,values[i],27,bold=True)
    text(x+20,261,metas[i],11,MUTED)

# Shared engine totals and daily chart: input + output includes reasoning once.
box(216,308,716,276);box(948,308,404,276)
text(236,329,'이용 추세',15,bold=True)
text(236,357,data['start'].replace('-','.')+' — '+data['end'].replace('-','.')+' · 일별 합계',11,MUTED)
button(788,328,124,'토큰 사용량',select=True)
base=526;left=278;chartw=624;chartH=126
top=max(10000,math.ceil(max(d['totalTokens'] for d in data['chart'])/10000)*10000)
for i in range(5):
    y=base-chartH*i/4
    line(left,y,910,y,'#EAF0F7')
    v=top*i/4
    text(238,y-5,f'{v/1000:g}k' if v>=1000 else str(int(v)),10,'#93A0B5')
slot=chartw/len(data['chart'])
for i,d in enumerate(data['chart']):
    x=left+slot*(i+.5)-16
    bh=d['inputTokens']/top*chartH;oh=d['outputTokens']/top*chartH
    if bh:box(x,base-bh,32,bh,'#AFC6E6','#AFC6E6',3)
    if oh:box(x,base-bh-oh,32,oh,BLUE,BLUE,3)
    text(x+16,540,d['date'][5:].replace('-','/'),10,'#93A0B5',align='center')
box(278,564,7,7,'#AFC6E6','#AFC6E6',2);text(292,561,'입력',10,MUTED)
box(344,564,7,7,BLUE,BLUE,2);text(358,561,'출력 (추론 포함)',10,MUTED)

text(968,329,'모델별 사용량',15,bold=True)
text(968,357,'같은 기간의 토큰과 예상 비용',11,MUTED)
box(968,384,364,37,'#F6F8FC','#F6F8FC',0)
text(978,397,'모델',11,MUTED,True);text(1220,397,'토큰',11,MUTED,True,'right');text(1322,397,'USD',11,MUTED,True,'right')
for i,m in enumerate(data['models']):
    y=436+i*48
    text(978,y,m['model'],12,'#405470')
    text(1220,y,n(m['totalTokens']),12,'#405470',align='right')
    text(1322,y,usd(m['estimatedUSD']),12,'#405470',align='right')
    line(968,y+29,1332,y+29,'#EFF2F7')
text(968,553,f"캐시 입력 {n(t['cachedTokens'])} · 추론 {n(t['reasoningTokens'])}",10,MUTED)

box(216,600,1136,256)
text(236,621,'사용 기록',15,bold=True)
text(1332,624,'선택 기간의 샘플 기록',11,MUTED,align='right')
text(236,659,'API 호출',12,BLUE,True);text(320,659,'생성 작업',12,MUTED)
line(236,684,1332,684);line(236,684,291,684,BLUE)
draw.rectangle((236*S,685*S,1332*S,721*S),fill='#F6F8FC')
cols=[246,490,805,915,1030,1170,1202]
head=['시간','모델','입력','출력','합계','USD','상태']
for i,h in enumerate(head):text(cols[i],697,h,11,MUTED,True,'right' if 2<=i<=5 else 'left')
for i,r in enumerate(data['calls'][:3]):
    y=737+i*39
    row=[r['Time'],r['Model'],n(r['Input']),n(r['Output']),n(r['Total']),usd(r['USD'])]
    for j,v in enumerate(row):text(cols[j],y,v,12,'#405470',align='right' if 2<=j<=5 else 'left')
    box(1202,y-4,45,23,'#EEF5F0','#EEF5F0',5);text(1211,y+2,r['Status'],10,'#648B78')
    line(236,y+27,1332,y+27,'#EFF2F7')

text(220,870,'디자인 참고 이미지입니다. 실제 Windows 앱 실행 화면을 캡처한 것은 아닙니다.',11,MUTED)
line(216,897,1352,897,'#E1E7F0')
text(216,915,'샘플 기록 · 내 프리셋을 등록해 시작하세요.',11,MUTED)
button(1058,902,62,'중지');button(1128,902,97,'결과 폴더');button(1233,902,119,'프리셋 생성',primary=True)
im.resize((W,H),Image.Resampling.LANCZOS).save(sys.argv[2])
print(sys.argv[2])
