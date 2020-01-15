!3/13/18: cleaned up a few more comments
!7/9/17: This code was generated by Emily Zakem and submitted as supporting information for the article "Ecological control of nitrite in the upper ocean."
!Note: As written, this model has options for 3 different P types and 3 zooplankton types, though only 1 for each is switched on: "p3" and "zoo3." It also has a placeholder in for another bacterial type ("bo_pa") though it is excluded in the equations

PROGRAM EZM

IMPLICIT NONE

INTEGER,PARAMETER :: ndays=1e4, &
	Hp=2000, & !change this scale below too
	dz=5, &  
	nz=Hp/dz
REAL*8,PARAMETER :: dt=0.02D0, & 
	!ndays=0.05D0, & !for fractions of days
	H=2D3, & 
	!
	!PHYSICAL params:
	euz=25D0, & !m euphotic zone (absorption by water molecules) 
	mlz=20D0, & !m mixed layer depth 
	o2sat=.2121D0, & !mol/m3 from calc_oxsat(25+273,35) in matlab. WOCE clim-avg surf T at 10S, E. Pac.
	Kgast=3D-5, & !m/s
	!deep oxygen relaxation
	o2satdeep=0.2D0, & !mol/m3, avg (for ~7 C) and 35
	t_o2relax=1D-2, & !1/day 
	kappazmin=5D-5, & !m2/s 
	kappazmax=1D-2, & !m2/s 
	Ws=10D0, & !m/day (range is 1-100) 
    !
	!BACTERIA METABOLISMS: 
	!
	!Bo: Aerobic Heterotroph
	yd_bo=0.14D0, & !mol cells/mol Detritus - aerobic bacteria yield
	yo_bo=yd_bo/20D0*4D0/(1D0-yd_bo), & !mol cells/mol O2 -where cells have 1mol N 
	enh4_bo=(1D0/yd_bo-1D0), & !production of ammonia per mol cells produced
	pd_max= 1D0, & !1/day - normalized max detritus uptake to match nitrate max uptake
	kd= 0.1D-3, & !org matter uptake half sat; used to be 5
	po_coef=2329100D0, & !m3/mol/day -
	!
	!Bnh4: Ammonia oxidizer
    ynh4_bnh4=1D0/112D0, &
    yo_bnh4=1D0/162D0, &
    eno2_bnh4=(1D0/ynh4_bnh4-1D0), & 
    pn_max= 50.8D0, & !mol DIN/mol biomass N/day
	kn= 0.133D-3, & !mol DIN/m3 
	!
	!Bno2: Nitrite oxidizer
    yno2_bno2=1D0/334D0, &
    yo_bno2=1D0/162D0, &
	eno3_bno2=(1D0/yno2_bno2-1D0), & 
	pn_max_noo= pn_max/2.1544D0, & !for 10x larger volume 
	kn_noo= kn*2.1544D0, & 
	!
	!P: phytoplankton
	umaxp=0.515D0, & !1/d -Ward 2014: 1*V^-0.15 for d=0.6 for Pro. max growth rate for p at 20C
	Iinmax=1400D0, & !W/m2 
	knh4= 0.0018D-3, & !mol/m3 Litchman scaling, with aV^b with a for knh4 from Ward 2014 
	kno2= 0.0036D-3, & !mol/m3 Litchman
	kno3= 0.0036D-3, & !mol/m3 Litchman
    chl2cmax=0.2D0, & !mg Chl/mmol C from Dutk 2015 
    chl2cmin=0.02D0, & !min Chl/mmol C 
    phimax=40D0, & !mmol C/mol photons/Ein  -quantum yield (mol C/mol photons)
    a_chl=0.02D0, & !m2/mg chl a -absorption parameter by chlorophyll 
    a_chlD=0.04D3, & !m2/g chl a -for light attenutation: chlorophyll plus CDOM
	convI=2.77D18/6.02D23*86400D0, & !from W/m2 to Ein/m2/d 2.77e18[quanta/W/s]*1/6.02e23[Einstein/quanta]. from MBARI: http://www3.mbari.org/bog/nopp/par.html
    !
    !Zooplankton:
    gmax=1D0, & !1/d
    kg=1D-3, & !mol/m3
    gam=0.5D0, & !growth yield for zoo 
    !
	!GRAZINGandMORTALITy:
	mlin=1D-2, & !linear mortality for b and p
	mquad=0D3, & !quadratic mortality for b and p
	mz=0.7D3, & !quadratic mortality for Z
	!
	!Oxygen ratio for pp production and zoo consumption:
    RredO=467D0/4D0/16D0, &
    !Temperature:
    TempAeArr = -4D3, &
    TemprefArr = 293.15D0, &    
    Tkel = 273.15D0, &
    TempCoeffArr = 0.8D0

INTEGER :: t,mlboxes,j,i,jc,nt,startSS,ind,recordDaily,dailycycle,dommodel,onep
REAL*8 :: zm(nz) = (/(j,j=0+dz/2,Hp-dz/2, dz)/)
REAL*8 :: z(nz+1) = (/(j,j=0,Hp, dz)/)
REAL*8 :: koverh, distn, adv, diff, cputime,dayint,dayint2,Iin
REAL*8,DIMENSION(:),ALLOCATABLE :: time, burial
REAL*8,DIMENSION(:,:),ALLOCATABLE :: sumall
REAL*8,DIMENSION(nz+1) :: w,wd,Kz,KzO
REAL*8,DIMENSION(nz+4) :: eqmask,inmask,Iz, & 
	u_bo,u_bo_pa,u_bnh4,u_bno2,u_p1,u_p2,u_p3,u_p3nolim,bt,pt,btsq,ptsq,g,g2,g3, &
    Biot,Chlt,po,pd,pdom,pnh4,pno2,pnh4b,pno2b,pno3,nlimtot,Temp,Q10r,TempFun, &  
	limnh4,limno2,limno3,inhibnh4, & !explicit limits to ease equations later
	limnh4b,limno2b, & !different n lims for the b
    nh4,no2,no3,ntot,o,bo,bo_pa,bnh4,bno2,d,dom,zoo,zoo2,zoo3,p1,xp1,p2,xp2,p3,xp3, &
	knh4A,knh4B,knh4C,knh4D,nh4A,nh4B,nh4C, &
	kno2A,kno2B,kno2C,kno2D,no2A,no2B,no2C, &
	kno3A,kno3B,kno3C,kno3D,no3A,no3B,no3C, &
	koA,koB,koC,koD,oA,oB,oC, &
	kboA,kboB,kboC,kboD,boA,boB,boC, &
	kbo_paA,kbo_paB,kbo_paC,kbo_paD,bo_paA,bo_paB,bo_paC, &
	kbnh4A,kbnh4B,kbnh4C,kbnh4D,bnh4A,bnh4B,bnh4C, &
	kbno2A,kbno2B,kbno2C,kbno2D,bno2A,bno2B,bno2C, &
	kdA,kdB,kdC,kdD,dA,dB,dC,kdomA,kdomB,kdomC,kdomD,domA,domB,domC, &
	kzooA,kzooB,kzooC,kzooD,zooA,zooB,zooC, &
	kzoo2A,kzoo2B,kzoo2C,kzoo2D,zoo2A,zoo2B,zoo2C, &
	kzoo3A,kzoo3B,kzoo3C,kzoo3D,zoo3A,zoo3B,zoo3C, &
	kp1A,kp1B,kp1C,kp1D,p1A,p1B,p1C, &
	kxp1A,kxp1B,kxp1C,kxp1D,xp1A,xp1B,xp1C, &
	kp2A,kp2B,kp2C,kp2D,p2A,p2B,p2C, &
	kxp2A,kxp2B,kxp2C,kxp2D,xp2A,xp2B,xp2C, &
	kp3A,kp3B,kp3C,kp3D,p3A,p3B,p3C, &
	kxp3A,kxp3B,kxp3C,kxp3D,xp3A,xp3B,xp3C, &
    no3uptakeP,no2emitP, &
    PC1,PCmax1,PC2,PCmax2,PC3,PCmax3,a_I,chl2c,chl2c_p1,chl2c_p2,chl2c_p3 !for Chl:C model

startSS=1 !set to 0 to define IC within this script 
dayint=10D0 !for recording frequency for resolved 1D for movies
dayint2=10D0 !for recording output frequency (replaced every time)
dailycycle=0 !for time-variant model resolving daily light cycle
recordDaily=0 !for recording each dt for movies of daily cycle
onep=1 !make just one pp type (P3)

kdA(:)=0D0
kdB(:)=0D0
kdC(:)=0D0
kdD(:)=0D0
!
kdomA(:)=0D0
kdomB(:)=0D0
kdomC(:)=0D0
kdomD(:)=0D0
!
knh4A(:)=0D0
knh4B(:)=0D0
knh4C(:)=0D0
knh4D(:)=0D0
kno2A(:)=0D0
kno2B(:)=0D0
kno2C(:)=0D0
kno2D(:)=0D0
kno3A(:)=0D0
kno3B(:)=0D0
kno3C(:)=0D0
kno3D(:)=0D0
!
kboA(:)=0D0
kboB(:)=0D0
kboC(:)=0D0
kboD(:)=0D0
!
kbnh4A(:)=0D0
kbnh4B(:)=0D0
kbnh4C(:)=0D0
kbnh4D(:)=0D0
kbno2A(:)=0D0
kbno2B(:)=0D0
kbno2C(:)=0D0
kbno2D(:)=0D0
koA(:)=0D0
koB(:)=0D0
koC(:)=0D0
koD(:)=0D0
!
kzooA(:)=0D0
kzooB(:)=0D0
kzooC(:)=0D0
kzooD(:)=0D0
kzoo2A(:)=0D0
kzoo2B(:)=0D0
kzoo2C(:)=0D0
kzoo2D(:)=0D0
kzoo3A(:)=0D0
kzoo3B(:)=0D0
kzoo3C(:)=0D0
kzoo3D(:)=0D0
!
kp1A(:)=0D0
kp1B(:)=0D0
kp1C(:)=0D0
kp1D(:)=0D0
!
kp2A(:)=0D0
kp2B(:)=0D0
kp2C(:)=0D0
kp2D(:)=0D0
!
kp3A(:)=0D0
kp3B(:)=0D0
kp3C(:)=0D0
kp3D(:)=0D0
!

print*,'Run for total n of days:';print*,ndays
print*,'1D version'
print*,'nz is:'; print*,nz

nt=ndays/dt

print*,'Number of days:'
print*,ndays
print*,'Number of timesteps:'
print*,nt

mlboxes=100D0/dz !discrete n of boxes in the mixed layer, close to 100m total sum
koverh=Kgast/100D0/mlboxes *3600D0*24D0 !gas transfer coefficient for each of the n boxes comprising the ml

ALLOCATE(time(nt))
ALLOCATE(burial(nt+1))
ind=ndays/dayint2
ALLOCATE(sumall(ind,17))

!sinking speed for detritus
wd(:)=Ws
wd(1)=0D0
wd(nz+1)=0D0

!1D model: no advection for other tracers
	w(:)=0D0
	wd=wd+w; !vertical velocity combination for detritus

!Diffusion:
Kz=(kappazmax*exp(-z/mlz)+kappazmin+1D-2*exp((z-H)/100D0))*3600D0*24D0 !larger at bottom boundary, too

Temp(:)=0D0 
Temp(3:nz+2)=12D0*exp(-zm/150D0)+12D0*exp(-zm/500D0)+2D0
TempFun = TempCoeffArr*exp(TempAeArr*(1D0/(Temp+Tkel)-1D0/TemprefArr))

KzO=Kz
KzO(1)=0D0
!for an open boundary: a sink for oxygen:
!KzO(nz+1)=(kappazmin+1D-2*exp((H-H)/100D0))*3600D0*24D0 
!for a closed boundary: a fixed o2
KzO(nz+1)=0D0

Kz(1)=0D0
Kz(nz+1)=0D0

eqmask(:)=0D0
eqmask(3:mlboxes+2)=1D0; !mask for air-sea equilibration

inmask(:)=0D0
inmask(3:nz+2)=1D0 !mask to zero out ghost cells for tracers and other quantities affecting tracers

!import previous steady state as IC:

if (startSS.eq.1) then

		OPEN(UNIT=3,FILE='ICfiles/nh4_fSS.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
		read(3,*) (nh4(J),J=1,nz+4)
		CLOSE(3)
		
		OPEN(UNIT=3,FILE='ICfiles/no2_fSS.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
		read(3,*) (no2(J),J=1,nz+4)
		CLOSE(3)
		
		OPEN(UNIT=3,FILE='ICfiles/no3_fSS.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
		read(3,*) (no3(J),J=1,nz+4)
		CLOSE(3)

		OPEN(UNIT=3,FILE='ICfiles/d_fSS.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
		read(3,*) (d(J),J=1,nz+4)
		CLOSE(3)
		
		OPEN(UNIT=3,FILE='ICfiles/dom_fSS.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
		read(3,*) (d(J),J=1,nz+4)
		CLOSE(3)

		OPEN(UNIT=3,FILE='ICfiles/o_fSS.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
		read(3,*) (o(J),J=1,nz+4)
		CLOSE(3)

		OPEN(UNIT=3,FILE='ICfiles/bo_fSS.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
		read(3,*) (bo(J),J=1,nz+4)
		CLOSE(3)

		OPEN(UNIT=3,FILE='ICfiles/bnh4_fSS.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
		read(3,*) (bnh4(J),J=1,nz+4)
		CLOSE(3)
		
		OPEN(UNIT=3,FILE='ICfiles/bno2_fSS.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
		read(3,*) (bno2(J),J=1,nz+4)
		CLOSE(3)

		OPEN(UNIT=3,FILE='ICfiles/zoo_fSS.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
		read(3,*) (zoo(J),J=1,nz+4)
		CLOSE(3)
		
		OPEN(UNIT=3,FILE='ICfiles/zoo2_fSS.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
		read(3,*) (zoo2(J),J=1,nz+4)
		CLOSE(3)
		
		OPEN(UNIT=3,FILE='ICfiles/zoo3_fSS.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
		read(3,*) (zoo3(J),J=1,nz+4)
		CLOSE(3)
		
        OPEN(UNIT=3,FILE='ICfiles/p1_fSS.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
		read(3,*) (p1(J),J=1,nz+4)
		CLOSE(3)

        OPEN(UNIT=3,FILE='ICfiles/p2_fSS.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
		read(3,*) (p2(J),J=1,nz+4)
		CLOSE(3)

        OPEN(UNIT=3,FILE='ICfiles/p3_fSS.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
		read(3,*) (p3(J),J=1,nz+4)
		CLOSE(3)

else
		!!Initial Conditions from simple distributions (may break now bc of steep gradients):
		nh4(:)=0.01D-3
		no2(:)=0.1D-3
		bo(:)=inmask*1D-5
		bnh4(:)=inmask*1D-5
		bno2(:)=inmask*1D-5
        p1(:)=inmask*1D-5
		p2(:)=inmask*1D-5
        p3(:)=inmask*1D-5

		o(:)=inmask*0.1D0 !mol/m3 crude estimate 
		zoo(:)=inmask*1D-5
		zoo2(:)=inmask*1D-5
		zoo3(:)=inmask*1D-5
		
        no3(3:nz+2)=0.03D0*(1D0-exp(-zm/200D0)) ! n increases with depth

		d(:)=0D0 !start with none

end if

if (onep.eq.1) then
    !take out p1 and p2:
    p1(:)=0D0
    p2(:)=0D0
end if

!take out zoo and zoo2
zoo(:)=0D0
zoo2(:)=0D0
!zoo3(:)=0D0

OPEN(UNIT=5,FILE='time_record.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)

if (recordDaily.eq.1) then

OPEN(UNIT=5,FILE='Iin.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)

OPEN(UNIT=5,FILE='Iz.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)

OPEN(UNIT=5,FILE='time_all.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)

OPEN(UNIT=5,FILE='nh4_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',STATUS='REPLACE')
CLOSE(5)	
OPEN(UNIT=5,FILE='no2_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',STATUS='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='no3_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',STATUS='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='d_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='dom_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='o_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)	
OPEN(UNIT=5,FILE='bo_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)	
OPEN(UNIT=5,FILE='bo_pa_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)	
OPEN(UNIT=5,FILE='bnh4_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='bno2_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='ubo_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='ubnh4_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='ubno2_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='up_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='zoo_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='zoo2_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='zoo3_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='p1_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='xp1_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='p2_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='p3_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='xp2_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)
OPEN(UNIT=5,FILE='xp3_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',status='REPLACE')
CLOSE(5)


end if 


print *,'Starting time loop:'
do t=1,nt


!LIGHT:
if (dailycycle.eq.1) then !Incoming light daily cycle:
    Iin=Iinmax/2D0*(cos(t*dt*2D0*3.1416D0)+1D0)
else !No daily cycle:
    Iin=Iinmax/2D0
end if

!chl impact on light:
Chlt=(p1*chl2c_p1+p2*chl2c_p2+p3*chl2c_p3)*6.6D0 !molN/m3 *mgChl/mmolC *5molC/molN = gChl

do j=1,nz
    Iz(j+2)=Iin*exp(-zm(j)*(1/euz+sum(Chlt(3:j+2)*a_chlD))) !this one sums the k at each depth
end do

i=dayint2*1000
j=t*dt*1000

if (MOD(j,i).eq.0) then
	!trace the integral:
	ind=t*dt/dayint2
	
	time(ind)=(t-1)*dt 

	ntot=nh4+no2+no3
	
	sumall(ind,1)=sum(o)*dz !mol/m3 times volume (with dx=1,dy=1)
	sumall(ind,2)=sum(d)*dz
	sumall(ind,3)=sum(dom)*dz
	sumall(ind,4)=sum(bo)*dz
	sumall(ind,5)=sum(bo_pa)*dz
	sumall(ind,6)=sum(bnh4)*dz
	sumall(ind,7)=sum(bno2)*dz
	sumall(ind,8)=sum(zoo)*dz
	sumall(ind,9)=sum(ntot)*dz
	sumall(ind,10)=sum(nh4)*dz
	sumall(ind,11)=sum(no2)*dz
	sumall(ind,12)=sum(no3)*dz
	sumall(ind,13)=sum(p1)*dz
	sumall(ind,14)=sum(p2)*dz
	sumall(ind,15)=sum(p3)*dz
	sumall(ind,16)=sum(zoo2)*dz
	sumall(ind,17)=sum(zoo3)*dz

end if

!get kA:
call MYRK(nh4,no3,no2,d,dom,o,zoo,zoo2,zoo3,p1,xp1,p2,xp2,p3,xp3, &
				bo,bo_pa,bnh4,bno2, & 
				knh4A,kno3A,kno2A,kdA,kdomA,koA,kzooA,kzoo2A,kzoo3A, &
                kp1A,kxp1A,kp2A,kxp2A,kp3A,kxp3A, &
				kboA,kbo_paA,kbnh4A,kbno2A)

!get yA:
nh4A = nh4 + dt/2D0*knh4A; 
no2A = no2 + dt/2D0*kno2A; 
no3A = no3 + dt/2D0*kno3A; 
boA = bo + dt/2D0*kboA; 
bnh4A = bnh4 + dt/2D0*kbnh4A; 
bno2A = bno2 + dt/2D0*kbno2A; 
dA = d + dt/2D0*kdA; 
oA = o + dt/2D0*koA; 
zooA = zoo + dt/2D0*kzooA; 
zoo2A = zoo2 + dt/2D0*kzoo2A; 
zoo3A = zoo3 + dt/2D0*kzoo3A; 
p1A = p1 + dt/2D0*kp1A;
p2A = p2 + dt/2D0*kp2A;
p3A = p3 + dt/2D0*kp3A;

call MYRK(nh4A,no3A,no2A,dA,domA,oA,zooA,zoo2A,zoo3A,p1A,xp1A,p2A,xp2A,p3A,xp3A, &
				boA,bo_paA,bnh4A,bno2A, & 
				knh4B,kno3B,kno2B,kdB,kdomB,koB,kzooB,kzoo2B,kzoo3B, &
                kp1B,kxp1B,kp2B,kxp2B,kp3B,kxp3B, &
				kboB,kbo_paB,kbnh4B,kbno2B)
	
!get yB:
nh4B = nh4 + dt/2D0*knh4B; 
no2B = no2 + dt/2D0*kno2B; 
no3B = no3 + dt/2D0*kno3B; 
boB = bo + dt/2D0*kboB; 
bnh4B = bnh4 + dt/2D0*kbnh4B; 
bno2B = bno2 + dt/2D0*kbno2B; 
dB = d + dt/2D0*kdB; 
oB = o + dt/2D0*koB; 
zooB = zoo + dt/2D0*kzooB; 
zoo2B = zoo2 + dt/2D0*kzoo2B; 
zoo3B = zoo3 + dt/2D0*kzoo3B; 
p1B = p1 + dt/2D0*kp1B;
p2B = p2 + dt/2D0*kp2B;
p3B = p3 + dt/2D0*kp3B;

call MYRK(nh4B,no3B,no2B,dB,domB,oB,zooB,zoo2B,zoo3B,p1B,xp1B,p2B,xp2B,p3B,xp3B, &
				boB,bo_paB,bnh4B,bno2B, & 
				knh4C,kno3C,kno2C,kdC,kdomC,koC,kzooC,kzoo2C,kzoo3C, &
                kp1C,kxp1C,kp2C,kxp2C,kp3C,kxp3C, &
				kboC,kbo_paC,kbnh4C,kbno2C)
				
!get yC:
nh4C = nh4 + dt*knh4B; 
no2C = no2 + dt*kno2B; 
no3C = no3 + dt*kno3B; 
boC = bo + dt*kboB; 
bnh4C = bnh4 + dt*kbnh4B; 
bno2C = bno2 + dt*kbno2B; 
dC = d + dt*kdB; 
oC = o + dt*koB; 
zooC = zoo + dt*kzooB; 
zoo2C = zoo2 + dt*kzoo2B; 
zoo3C = zoo3 + dt*kzoo3B; 
p1C = p1 + dt*kp1B;
p2C = p2 + dt*kp2B;
p3C = p3 + dt*kp3B;

call MYRK(nh4C,no3C,no2C,dC,domC,oC,zooC,zoo2C,zoo3C,p1C,xp1C,p2C,xp2C,p3C,xp3C, &
				boC,bo_paC,bnh4C,bno2C, & 
				knh4D,kno3D,kno2D,kdD,kdomD,koD,kzooD,kzoo2D,kzoo3D, &
                kp1D,kxp1D,kp2D,kxp2D,kp3D,kxp3D, &
				kboD,kbo_paD,kbnh4D,kbno2D)
	
nh4 = nh4 + dt/6D0*(knh4A + 2D0*knh4B + 2D0*knh4C + knh4D);
no2 = no2 + dt/6D0*(kno2A + 2D0*kno2B + 2D0*kno2C + kno2D);
no3 = no3 + dt/6D0*(kno3A + 2D0*kno3B + 2D0*kno3C + kno3D);
bo = bo + dt/6D0*(kboA + 2D0*kboB + 2D0*kboC + kboD);
bnh4 = bnh4 + dt/6D0*(kbnh4A + 2D0*kbnh4B + 2D0*kbnh4C + kbnh4D);
bno2 = bno2 + dt/6D0*(kbno2A + 2D0*kbno2B + 2D0*kbno2C + kbno2D);
d = d + dt/6D0*(kdA + 2D0*kdB + 2D0*kdC + kdD);
o = o + dt/6D0*(koA + 2D0*koB + 2D0*koC + koD);	
zoo = zoo + dt/6D0*(kzooA + 2D0*kzooB + 2D0*kzooC + kzooD);	
zoo2 = zoo2 + dt/6D0*(kzoo2A + 2D0*kzoo2B + 2D0*kzoo2C + kzoo2D);	
zoo3 = zoo3 + dt/6D0*(kzoo3A + 2D0*kzoo3B + 2D0*kzoo3C + kzoo3D);	
if (onep.eq.0) then
    p1 = p1 + dt/6D0*(kp1A + 2D0*kp1B + 2D0*kp1C + kp1D);	
    p2 = p2 + dt/6D0*(kp2A + 2D0*kp2B + 2D0*kp2C + kp2D);	
end if
p3 = p3 + dt/6D0*(kp3A + 2D0*kp3B + 2D0*kp3C + kp3D);	


if (recordDaily.eq.1) then

!append at every time step:
print*,t*dt		
	OPEN(UNIT=7,FILE='Iin.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
	WRITE(7,*) (Iin)
	CLOSE(7)

OPEN(UNIT=5,FILE='Iz.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (Iz)
CLOSE(5)	

print*,t*dt		
	OPEN(UNIT=7,FILE='time_all.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
	WRITE(7,*) (t*dt)
	CLOSE(7)	

OPEN(UNIT=5,FILE='nh4_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (nh4)
CLOSE(5)	
OPEN(UNIT=5,FILE='no2_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (no2)
CLOSE(5)
OPEN(UNIT=5,FILE='no3_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (no3)
CLOSE(5)
OPEN(UNIT=5,FILE='d_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (d)
CLOSE(5)
OPEN(UNIT=5,FILE='dom_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (dom)
CLOSE(5)
OPEN(UNIT=5,FILE='o_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (o)
CLOSE(5)	
OPEN(UNIT=5,FILE='bo_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (bo)
CLOSE(5)	
OPEN(UNIT=5,FILE='bo_pa_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (bo_pa)
CLOSE(5)	
OPEN(UNIT=5,FILE='bnh4_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (bnh4)
CLOSE(5)
OPEN(UNIT=5,FILE='bno2_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (bno2)
CLOSE(5)
OPEN(UNIT=5,FILE='ubo_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (u_bo)
CLOSE(5)
OPEN(UNIT=5,FILE='ubnh4_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (u_bnh4)
CLOSE(5)
OPEN(UNIT=5,FILE='ubno2_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (u_bno2)
CLOSE(5)
OPEN(UNIT=5,FILE='up1_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (u_p1)
CLOSE(5)
OPEN(UNIT=5,FILE='up2_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (u_p2)
CLOSE(5)
OPEN(UNIT=5,FILE='up3_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (u_p3)
CLOSE(5)
OPEN(UNIT=5,FILE='zoo_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (zoo)
CLOSE(5)
OPEN(UNIT=5,FILE='zoo2_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (zoo2)
CLOSE(5)
OPEN(UNIT=5,FILE='zoo3_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (zoo3)
CLOSE(5)
OPEN(UNIT=5,FILE='p1_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (p1)
CLOSE(5)	
OPEN(UNIT=5,FILE='xp1_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (xp1)
CLOSE(5)	
OPEN(UNIT=5,FILE='p2_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (p2)
CLOSE(5)	
OPEN(UNIT=5,FILE='xp2_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (xp2)
CLOSE(5)	
OPEN(UNIT=5,FILE='p3_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (p3)
CLOSE(5)	
OPEN(UNIT=5,FILE='xp3_fa.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
WRITE(5,*) (xp3)
CLOSE(5)	

end if

if (MOD(t*dt,1.00).eq.0) then
	print*,t*dt		
	OPEN(UNIT=7,FILE='time_record.txt',ACCESS='SEQUENTIAL',BLANK='ZERO',POSITION='APPEND')
	WRITE(7,*) (t*dt)
	CLOSE(7)	
end if

if ((MOD(t*dt,dayint).eq.0).OR.(t*dt.eq.ndays)) then

    
OPEN(UNIT=6,FILE='chl2c_p1.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (chl2c_p1(J),J=1,nz+4)
CLOSE(6)
OPEN(UNIT=6,FILE='chl2c_p2.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (chl2c_p2(J),J=1,nz+4)
CLOSE(6)
OPEN(UNIT=6,FILE='chl2c_p3.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (chl2c_p3(J),J=1,nz+4)
CLOSE(6)
OPEN(UNIT=6,FILE='chl2c.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (chl2c(J),J=1,nz+4)
CLOSE(6)

!NOTE: using no3uptakeP as a placeholder for recording multiple quantities for N fluxes:
!diff
    do j=1,nz ; jc=j+2;
        call mydiff(no2,Kz,j,dz,nz,diff)
            no3uptakeP(jc)=diff
    end do
OPEN(UNIT=6,FILE='kno2_diff.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (no3uptakeP(J),J=1,nz+4)
CLOSE(6)

!source: NH4 oxidizer:
no3uptakeP=eno2_bnh4*u_bnh4*bnh4
OPEN(UNIT=6,FILE='kno2_nh4oxid.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (no3uptakeP(J),J=1,nz+4)
CLOSE(6)

!sink: NO2 oxidizer:
no3uptakeP=-1/yno2_bno2*u_bno2*bno2
OPEN(UNIT=6,FILE='kno2_no2oxid.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (no3uptakeP(J),J=1,nz+4)
CLOSE(6)

!sink: phytopl 2 use:
no3uptakeP=-u_p2*p2*limno2/(limnh4+limno2+1D-38)
OPEN(UNIT=6,FILE='kno2_p2use.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (no3uptakeP(J),J=1,nz+4)
CLOSE(6)

!sink: phytopl 3 use of nitrite:
no3uptakeP=-u_p3*p3*limno2/(limnh4+limno2+limno3+1D-38)
OPEN(UNIT=6,FILE='kno2_p3use.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (no3uptakeP(J),J=1,nz+4)
CLOSE(6)

!source: phytopl 3 emit:
OPEN(UNIT=6,FILE='kno2_p3emit.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (no2emitP(J),J=1,nz+4)
CLOSE(6)


!!now, the pp uptake of each N:
!no3 uptake by pp3
no3uptakeP=-u_p3*p3*limno3/(nlimtot+1D-38) !more than based on just u_p bc of inefficiency
OPEN(UNIT=6,FILE='P3uptakeNO3.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (no3uptakeP(J),J=1,nz+4)
CLOSE(6)

!no2 uptake by pp2: (still using no3uptake as placeholder): (this is redundant with above kno2_puse.txt)
no3uptakeP=-u_p2*p2*limno2/(limnh4+limno2+1D-38)
OPEN(UNIT=6,FILE='P2uptakeNO2.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (no3uptakeP(J),J=1,nz+4)
CLOSE(6)

!no2 uptake by pp3: (still using no3uptake as placeholder): (this is redundant with above kno2_puse.txt)
no3uptakeP=-u_p3*p3*limno2/(nlimtot+1D-38)
OPEN(UNIT=6,FILE='P3uptakeNO2.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (no3uptakeP(J),J=1,nz+4)
CLOSE(6)

!nh4 uptake by pp1: (still using no3uptake as placeholder): (this is redundant with above kno2_puse.txt)
no3uptakeP=-u_p1*p1!*limnh4/(nlimtot+1D-38)
OPEN(UNIT=6,FILE='P1uptakeNH4.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (no3uptakeP(J),J=1,nz+4)
CLOSE(6)

!nh4 uptake by pp2: (still using no3uptake as placeholder): (this is redundant with above kno2_puse.txt)
no3uptakeP=-u_p2*p2*limnh4/(limnh4+limno2+1D-38)
OPEN(UNIT=6,FILE='P2uptakeNH4.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (no3uptakeP(J),J=1,nz+4)
CLOSE(6)

!nh4 uptake by pp3: (still using no3uptake as placeholder): (this is redundant with above kno2_puse.txt)
no3uptakeP=-u_p3*p3*limnh4/(nlimtot+1D-38)
OPEN(UNIT=6,FILE='P3uptakeNH4.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (no3uptakeP(J),J=1,nz+4)
CLOSE(6)

!also record diffusion of nitrate:
    do j=1,nz ; jc=j+2;
        call mydiff(no3,Kz,j,dz,nz,diff)
            no3uptakeP(jc)=diff
    end do
OPEN(UNIT=6,FILE='kno3_diff.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (no3uptakeP(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='wd.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (wd(J),J=1,nz+1)
CLOSE(6)

OPEN(UNIT=6,FILE='kz.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (kz(J),J=1,nz+1)
CLOSE(6)

OPEN(UNIT=6,FILE='Iz.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (Iz(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='nh4_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (nh4(J),J=1,nz+4)
CLOSE(6)
	
OPEN(UNIT=6,FILE='no2_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (no2(J),J=1,nz+4)
CLOSE(6)
	
OPEN(UNIT=6,FILE='no3_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (no3(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='d_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (d(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='dom_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (dom(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='o_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (o(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='bo_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (bo(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='ubo_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (u_bo(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='ubnh4_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (u_bnh4(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='ubno2_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (u_bno2(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='up1_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (u_p1(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='up2_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (u_p2(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='up3_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (u_p3(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='bo_pa_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (bo_pa(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='bnh4_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (bnh4(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='bno2_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (bno2(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='zoo_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (zoo(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='zoo2_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (zoo2(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='zoo3_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (zoo3(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='p1_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (p1(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='xp1_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (xp1(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='p2_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (p2(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='xp2_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (xp2(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='p3_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (p3(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='xp3_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
WRITE(*,*) (xp3(J),J=1,nz+4)
CLOSE(6)

OPEN(UNIT=6,FILE='time_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
DO J=1,ind
WRITE(*,*) (time(J))
END DO
CLOSE(6)

OPEN(UNIT=6,FILE='z_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
DO I=1,nz
WRITE(*,*) (zm(I))
END DO
CLOSE(6)

OPEN(UNIT=6,FILE='sumall_f.txt',ACCESS='SEQUENTIAL',BLANK='ZERO')
DO I=1,ind
WRITE(*,*) (sumall(I,J),J=1,17)
END DO
CLOSE(6)

	end if  !end the mod

end do !!end time loop

print*,'Total CPU time in seconds:'
call CPU_TIME(cputime)
print*,cputime


contains
SUBROUTINE MYQUICK(C,w,j,dz,nz,adv)
implicit none
REAL*8 :: C(nz+4),w(nz+1),adv
REAL*8 :: wp1,wn1,wp,wn,Dy1,Dy2,Dyn1,Fu,Fd
INTEGER :: j,nz,dz
INTEGER :: jc

jc=j+2

        !at top face:
        wp1=(w(j+1)+abs(w(j+1)))/2D0;
        wn1=(w(j+1)-abs(w(j+1)))/2D0;
        !at bottom face:
        wp=(w(j)+abs(w(j)))/2D0;
        wn=(w(j)-abs(w(j)))/2D0;
          
        Dy1=C(jc+2)-2D0*C(jc+1)+C(jc);
        Dy2=C(jc+1)-2D0*C(jc)+C(jc-1);
        Dyn1=C(jc)-2D0*C(jc-1)+C(jc-2);

        Fu=w(j+1)/2D0*(C(jc)+C(jc+1)) - wp1/8D0*Dy2 - wn1/8D0*Dy1;
        Fd=w(j)/2D0*(C(jc-1)+C(jc)) - wp/8D0*Dyn1 - wn/8D0*Dy2;
                
		adv=(Fu-Fd)/dz;  
        
END SUBROUTINE MYQUICK

SUBROUTINE MYDIFF(C,Kz,j,dz,nz,diff)
implicit none
REAL*8 :: C(nz+4),Kz(nz+1),diff
REAL*8 :: Fu,Fd
INTEGER :: j,nz,dz
INTEGER :: jc

jc=j+2
        
        Fu=Kz(j+1)*(C(jc+1)-C(jc))/dz;
        Fd=Kz(j)*(C(jc)-C(jc-1))/dz;
               
        diff=(Fu-Fd)/dz;
        
END SUBROUTINE MYDIFF


SUBROUTINE MYRK(nh4_one,no3_one,no2_one,d_one,dom_one,o_one, &
                zoo_one,zoo2_one,zoo3_one, &
				p1_one,xp1_one,p2_one,xp2_one,p3_one,xp3_one, &
				bo_one,bo_pa_one,bnh4_one,bno2_one, & 
				knh4_two,kno3_two,kno2_two,kd_two,kdom_two,ko_two, &
                kzoo_two,kzoo2_two,kzoo3_two, &
				kp1_two,kxp1_two,kp2_two,kxp2_two,kp3_two,kxp3_two, &
				kbo_two,kbo_pa_two,kbnh4_two,kbno2_two)
				
implicit none
REAL*8, dimension(nz+4), intent(in) :: nh4_one,no3_one,no2_one,d_one,dom_one,o_one, &
				zoo_one,zoo2_one,zoo3_one,p1_one,xp1_one,p2_one,xp2_one,p3_one,xp3_one, &
				bo_one,bo_pa_one,bnh4_one,bno2_one
REAL*8, dimension(nz+4), intent(out) :: knh4_two,kno3_two,kno2_two,kd_two, &
				kdom_two,ko_two,kzoo_two,kzoo2_two,kzoo3_two, &
                kp1_two,kxp1_two,kp2_two,kxp2_two,kp3_two,kxp3_two, &
				kbo_two,kbo_pa_two,kbnh4_two,kbno2_two

    do j=1,nz ; jc=j+2;       
    	call mydiff(nh4_one,Kz,j,dz,nz,diff)
			knh4_two(jc)=diff
			call mydiff(no2_one,Kz,j,dz,nz,diff)
			kno2_two(jc)=diff
			call mydiff(no3_one,Kz,j,dz,nz,diff)
            kno3_two(jc)=diff
			call mydiff(bo_one,Kz,j,dz,nz,diff)
			kbo_two(jc)=diff
		    call myquick(bo_pa_one,wd,j,dz,nz,adv)
			call mydiff(bo_pa_one,Kz,j,dz,nz,diff)
        	kbo_pa_two(jc)=-adv+diff
        	call mydiff(bnh4_one,Kz,j,dz,nz,diff)
        	kbnh4_two(jc)=diff
        	call mydiff(bno2_one,Kz,j,dz,nz,diff)
        	kbno2_two(jc)=diff
        	call myquick(d_one,wd,j,dz,nz,adv)
        	call mydiff(d_one,Kz,j,dz,nz,diff)
        	kd_two(jc)=-adv+diff
        	call mydiff(dom_one,Kz,j,dz,nz,diff)
        	kdom_two(jc)=diff
        	call mydiff(o_one,KzO,j,dz,nz,diff)
        	ko_two(jc)=diff
        	call mydiff(zoo_one,Kz,j,dz,nz,diff)
        	kzoo_two(jc)=diff
        if (onep.eq.0) then
            call mydiff(p1_one,Kz,j,dz,nz,diff)
        	kp1_two(jc)=diff
        	!call mydiff(xp1_one,Kz,j,dz,nz,diff)
        	!kxp1_two(jc)=diff
        	call mydiff(p2_one,Kz,j,dz,nz,diff)
        	kp2_two(jc)=diff
        	!call mydiff(xp2_one,Kz,j,dz,nz,diff)
        	!kxp2_two(jc)=diff
        end if
            call mydiff(p3_one,Kz,j,dz,nz,diff)
        	kp3_two(jc)=diff
        	!call mydiff(xp3_one,Kz,j,dz,nz,diff)
        	!kxp3_two(jc)=diff
        	call mydiff(zoo2_one,Kz,j,dz,nz,diff)
        	kzoo2_two(jc)=diff
        	call mydiff(zoo3_one,Kz,j,dz,nz,diff)
        	kzoo3_two(jc)=diff

end do

bt=bo_one+bnh4_one+bno2_one
pt=p1_one+p2_one+p3_one
btsq=bo_one*bo_one+bnh4_one*bnh4_one+bno2_one*bno2_one
ptsq=p1_one*p1_one+p2_one*p2_one+p3_one*p3_one

!uptake limitations for bacteria/archaea:
po=po_coef*o_one*TempFun 
pd=pd_max*(d_one/(d_one+kd))*TempFun 

limnh4b=(nh4_one/(nh4_one+kn))!*TempFun
limno2b=(no2_one/(no2_one+kn_noo))!*TempFun

!pnh4b=pn_max*limnh4b*TempFun 
!pno2b=pn_max_noo*limno2b*TempFun 
!now with no Temp: Horak 2013
pnh4b=pn_max*limnh4b 
pno2b=pn_max_noo*limno2b 

!Bacteria growth rates:

u_bo=min(po*yo_bo,pd*yd_bo)
u_bnh4=min(pnh4b*ynh4_bnh4,po*yo_bnh4)
u_bno2=min(pno2b*yno2_bno2,po*yo_bno2)

!uptake limitations for phytopp
limnh4=(nh4_one/(nh4_one+knh4))
limno2=(no2_one/(no2_one+kno2))
limno3=(no3_one/(no3_one+kno3))
nlimtot=min(1D0,limnh4+limno2+limno3)

!Geider chlorophyll:c based growth rates:
PCmax1 = 1D0*umaxp*TempFun*limnh4
PCmax2 = 1D0*umaxp*TempFun*min(1D0,limnh4+limno2)
PCmax3 = 1D0*umaxp*TempFun*nlimtot
a_I = phimax*a_chl*Iz*convI !mmol C/mol Ein * m2/mg chla * Ein/m2/d = mmol C/mg chla/d
chl2c_p1 = max(chl2cmin, min(chl2cmax, chl2cmax/(1D0+chl2cmax*a_I/2D0/PCmax1)))
chl2c_p2 = max(chl2cmin, min(chl2cmax, chl2cmax/(1D0+chl2cmax*a_I/2D0/PCmax2)))
chl2c_p3 = max(chl2cmin, min(chl2cmax, chl2cmax/(1D0+chl2cmax*a_I/2D0/PCmax3)))
chl2c = chl2c_p3
PC1 = PCmax1*(1D0 - exp(-a_I*chl2c_p1/PCmax1))
PC2 = PCmax2*(1D0 - exp(-a_I*chl2c_p2/PCmax2))
PC3 = PCmax3*(1D0 - exp(-a_I*chl2c_p3/PCmax3))

u_p1=PC1
u_p2=PC2
u_p3=PC3

!grazing: type II
!g=gmax*bt/(bt+kg)*TempFun !for zoo
!g2=gmax*pt/(pt+kg)*TempFun !for zoo2
g3=gmax*(bt+pt)/(bt+pt+kg)*TempFun !for zoo3 (goal: ONLY this one)

!EQUATIONS:

knh4_two = knh4_two &
			+ enh4_bo*u_bo*bo_one & !2 aerobic hets
            + (1D0-gam)*g*zoo_one &  !zoo
			+ (1D0-gam)*g2*zoo2_one  & !zoo2
			+ (1D0-gam)*g3*zoo3_one &  !zoo
			- 1D0/ynh4_bnh4*u_bnh4*bnh4_one & !consumption: NH4 oxidizer 
			- u_p1*p1_one & 
            - u_p2*p2_one*limnh4/(limnh4+limno2+1D-38) &
            - u_p3*p3_one*limnh4/(limnh4+limno2+limno3+1D-38) 

kno2_two = kno2_two &
			+ eno2_bnh4*u_bnh4*bnh4_one & !source: NH4 oxidizer 
			- 1D0/yno2_bno2*u_bno2*bno2_one & !sink: aerobic NO2 oxidizer
            - u_p2*p2_one*limno2/(limnh4+limno2+1D-38) & !pp
            - u_p3*p3_one*limno2/(limnh4+limno2+limno3+1D-38) 
		
kno3_two = kno3_two &
			+ eno3_bno2*u_bno2*bno2_one & !source: aerobic NO2 oxidizer
            - u_p3*p3_one*limno3/(limnh4+limno2+limno3+1D-38) !no3uptakeP
	   						

kbo_two= kbo_two +  bo_one*(u_bo - mlin*TempFun - mquad*bo_one*TempFun - g*zoo_one/(bt+1D-38) &
         - g3*zoo3_one/(bt+pt+1D-38)) !
kbnh4_two= kbnh4_two +  bnh4_one*(u_bnh4 - mlin*TempFun - mquad*bnh4_one*TempFun - g*zoo_one/(bt+1D-38) &
           - g3*zoo3_one/(bt+pt+1D-38))
kbno2_two= kbno2_two +  bno2_one*(u_bno2 - mlin*TempFun - mquad*bno2_one*TempFun - g*zoo_one/(bt+1D-38) &
           - g3*zoo3_one/(bt+pt+1D-38))

kp1_two = kp1_two + p1_one*(u_p1 - mlin*TempFun - mquad*p1_one*TempFun - g2*zoo2_one/(pt+1D-38) - g3*zoo3_one/(bt+pt+1D-38))
kp2_two = kp2_two + p2_one*(u_p2 - mlin*TempFun - mquad*p2_one*TempFun - g2*zoo2_one/(pt+1D-38) - g3*zoo3_one/(bt+pt+1D-38))
kp3_two = kp3_two + p3_one*(u_p3 - mlin*TempFun - mquad*p3_one*TempFun - g2*zoo2_one/(pt+1D-38) - g3*zoo3_one/(bt+pt+1D-38))

kzoo_two=kzoo_two + gam*g*zoo_one - mz*zoo_one*zoo_one*TempFun
kzoo2_two=kzoo2_two + gam*g2*zoo2_one - mz*zoo2_one*zoo2_one*TempFun
kzoo3_two=kzoo3_two + gam*g3*zoo3_one - mz*zoo3_one*zoo3_one*TempFun

kd_two= kd_two &
		+ mlin*(bt+pt)*TempFun &
		+ mquad*(btsq+ptsq)*TempFun &
		+ mz*zoo_one*zoo_one*TempFun &!quadratic
		+ mz*zoo2_one*zoo2_one*TempFun &!quadratic
		+ mz*zoo3_one*zoo3_one*TempFun & !quadratic
		- 1D0/yd_bo*u_bo*bo_one !sink: 1 heterotroph

ko_two = ko_two &
		+ RredO*(u_p1*p1_one + u_p2*p2_one + u_p3*p3_one) & !pp production
        - RredO*(1D0-gam)*g*zoo_one & !zoo use
		- RredO*(1D0-gam)*g2*zoo2_one & !zoo2 use
		- RredO*(1D0-gam)*g3*zoo3_one & !zoo2 use
		- 1D0/yo_bo*u_bo*bo_one & !het B use
		- 1D0/yo_bnh4*u_bnh4*bnh4_one & !NH4 oxid use
		- 1D0/yo_bno2*u_bno2*bno2_one & !NO2 oxid use
		+ koverh*(o2sat-o_one)*eqmask & !air-sea
		+ t_o2relax*(o2satdeep-o_one)*inmask  !relaxation at depth (lateral flux)


        
END SUBROUTINE MYRK

END PROGRAM EZM


