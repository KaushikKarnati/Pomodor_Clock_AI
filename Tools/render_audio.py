import re,base64,pathlib,math,wave,struct,random
project=pathlib.Path(__file__).resolve().parents[1]
root=project/'Resources'
s=(project/'Reference/ClaudeArtifact.html').read_text()
m=re.search(r'id="tomatoImg"[^>]+src="data:image/webp;base64,([^"]+)',s)
(root/'tomato.webp').write_bytes(base64.b64decode(m[1]))
rate=48000
rng=random.Random(1046)
noise=[rng.uniform(-1,1)*(1-i/(rate*.03)) for i in range(int(rate*.03))]
def save(name,x):
 with wave.open(str(root/(name+'.wav')),'wb') as w:
  w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate)
  assert max(map(abs,x))<1,(name,max(map(abs,x)))
  w.writeframes(b''.join(struct.pack('<h',round(v*32767)) for v in x))
# Web Audio bandpass: constant 0 dB peak, Q=6, exponential gain ramp.
for name,f,g,d in [('tickOdd',3300,.22,.018),('tickEven',4100,.22,.018),('ratchet',5200,.3,.012)]:
 omega=2*math.pi*f/rate;alpha=math.sin(omega)/12;a0=1+alpha
 b0=alpha/a0;b2=-alpha/a0;a1=-2*math.cos(omega)/a0;a2=(1-alpha)/a0
 x1=x2=y1=y2=0;out=[]
 for i in range(int(rate*(d+.01))):
  x=noise[i] if i<len(noise) else 0
  y=b0*x+b2*x2-a1*y1-a2*y2;x2=x1;x1=x;y2=y1;y1=y
  env=g*(.0001/g)**min(1,i/rate/d)
  out.append(y*env)
 save(name,out)
out=[0.0]*int(rate*2.15)
for k in range(34):
 t0=k*.056+(.006 if k%2 else 0);env=(34-k)/9 if k>25 else 1
 for f,g,d in [(2350,.5,.22),(3790,.24,.12),(5230,.12,.07)]:
  f*=1+((k%3)-1)*.002;peak=g*env+.0001
  for i in range(int((d+.02)*rate)):
   t=i/rate;j=round(t0*rate)+i
   amp=.0001*(peak/.0001)**(t/.003) if t<.003 else peak*(.0001/peak)**min(1,(t-.003)/(d-.003))
   if j<len(out):out[j]+=.32*amp*math.sin(2*math.pi*f*t)
save('bell',out)
