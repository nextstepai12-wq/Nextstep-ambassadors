(function(){const c=document.createElement("canvas");c.id="bg";document.body.prepend(c);const x=c.getContext("2d"),red=matchMedia("(prefers-reduced-motion:reduce)").matches,dpr=Math.min(2,devicePixelRatio||1);
let W,H,mx=0,my=0,t=0;function rs(){W=innerWidth;H=innerHeight;c.width=W*dpr;c.height=H*dpr;x.setTransform(dpr,0,0,dpr,0,0)}rs();addEventListener("resize",rs);addEventListener("pointermove",e=>{mx=e.clientX/W-.5;my=e.clientY/H-.5});
const OR=[[.12,.18,300,"37,99,235",.9],[.9,.12,340,"6,182,212",1.1],[.75,.8,300,"16,185,129",.7],[.2,.85,260,"37,99,235",1.3]];
const COLS=W<700?26:44,ROWS=W<700?16:24;
function frame(){t+=.012;const g=x.createLinearGradient(0,0,0,H);g.addColorStop(0,"#f8fafc");g.addColorStop(1,"#eaf2ff");x.fillStyle=g;x.fillRect(0,0,W,H);
OR.forEach(([ox,oy,r,col,sp],i)=>{const px=ox*W+Math.sin(t*sp+i)*60+mx*40,py=oy*H+Math.cos(t*sp*.8+i)*50+my*30,rg=x.createRadialGradient(px,py,0,px,py,r);rg.addColorStop(0,"rgba("+col+",.2)");rg.addColorStop(1,"rgba("+col+",0)");x.fillStyle=rg;x.fillRect(0,0,W,H)});
const f=520,cx=W/2+mx*50,cy=H*.78+my*20,s=Math.max(34,W/COLS*1.5);
for(let j=ROWS;j>=0;j--){for(let i=-COLS;i<=COLS;i++){const X=i*s*.55,Z=j*s*.55+40,Y=Math.sin(i*.28+t*1.4)*34+Math.cos(j*.45+t)*30,k=f/(f+Z),sx=cx+X*k,sy=cy+(Y+170)*k-Z*.18*k*0+(-j*7);if(sx<-10||sx>W+10)continue;const a=Math.max(0,1-j/ROWS)*.55,r=Math.max(.5,2.4*k);x.fillStyle=(i+j)%3===0?"rgba(6,182,212,"+a+")":"rgba(37,99,235,"+a*.8+")";x.beginPath();x.arc(sx,sy,r,0,6.283);x.fill()}}
if(!red)requestAnimationFrame(frame)}frame()})();
