import csv, math, sys
def normals(f):
    r=list(csv.DictReader(open(f)))
    tx=[(float(x['MLY-TMAX-NORMAL'])-32)/1.8 for x in r]; tn=[(float(x['MLY-TMIN-NORMAL'])-32)/1.8 for x in r]
    return tx,tn,float(r[0]['LATITUDE']),r[0]['NAME']
def t_high(tair,lat,H): return 54.32+0.78*tair-0.0025*lat*lat-15.14*math.log10(H+25)   # FHWA-RD-97-103 eq 8
def t_low(tair,lat,H): return -1.56+0.72*tair-0.004*lat*lat+6.26*math.log10(H+25)     # eq 7
R=0.008314; Af,Eaf,Ac,Eac=1.25e13,95.04,3.68e7,62.21   # NCHRP 871 Table 16 (973 prints Af 1.25e3: misprint); per day
def F(t,T,M):
    kf=Af*math.exp(-Eaf/(R*T)); kc=Ac*math.exp(-Eac/(R*T))
    return M*((1-kc/kf)*(1-math.exp(-kf*t))+kc*t)
def teq(x,T,M):
    lo,hi=0.0,1.0
    while F(hi,T,M)<x: hi*=2
    for _ in range(60):
        mid=(lo+hi)/2
        if F(mid,T,M)<x: lo=mid
        else: hi=mid
    return hi
def run(f,years=20,HPG=64.0,H=0.0):
    tx,tn,lat,name=normals(f)
    g0=6.552/(1+(HPG/107.167)**-4.068); M=0.94/(1+(HPG/82.68)**7.96)
    mid=[15.2+30.4*m for m in range(12)]
    def interp(arr,d):
        for m in range(12):
            a=mid[m]; b=a+30.4; dd=d if d>=mid[0] else d+365
            if a<=dd<b or m==11: return arr[m]+(arr[(m+1)%12]-arr[m])*min(max((dd-a)/30.4,0),1)
    x=0.0; out={}
    hours=0
    for y in range(years):
        for d in range(365):
            hi=t_high(interp(tx,d),lat,H); lo=t_low(interp(tn,d),lat,H)
            for h in range(24):
                s=(1-math.cos(math.pi*(h-6)/9))/2 if 6<=h<=15 else (1+math.cos(math.pi*((h-15)%24)/15))/2
                T=lo+(hi-lo)*s+273.15
                if T<293.15: continue
                if y==0: hours+=1
                x=F(teq(x,T,M)+1/24.0,T,M)
        out[y+1]=x/M
    N=0.477*math.exp(-0.226*out[10]); APmax=(4.5-g0)/M
    print(f"{name} (lat {lat:.1f}), PG {HPG:.0f}: log|G*|0 {g0:.2f}, M {M:.3f}; pavement surface July high {t_high(tx[6],lat,0):.0f} C, Jan low {t_low(tn[0],lat,0):.0f} C; {hours} h/yr above 20 C")
    for yr in (1,2,3,5,10,15,20):
        AP=out[yr]; prof=[g0+M*((0.916*z+APmax)/(z+1))*(1-math.exp(-N*AP)) for z in (0,1,2,4,6)]
        print(f"  year {yr:2d}: kinetics log|G*| {g0+M*AP:.2f} | PAM z=0,1,2,4,6 cm: "+", ".join(f"{p:.2f}" for p in prof)+f" | surface progress {1-math.exp(-N*AP):.2f}")
for f in sys.argv[1:]: run(f)
