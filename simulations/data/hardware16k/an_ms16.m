H='C:/Users/Nogiku/AppData/Local/Temp/claude/163a9fc9a304703e/67da9375-757e-4d7c-8f6c-2a0d19d37214/scratchpad/hw';
S=load(fullfile(H,NAME+".mat")); D=load(fullfile(H,NAME+"_design.mat")); r=structfun(@double,S.raw,'UniformOutput',false);
P=D.P; Ts=D.Ts; np=floor(numel(r.current_cmd)/P); per=3:np; % drop 2 transient periods
fprintf('pos range [%.3f %.3f] rad, max|v| true %.1f, twist max %.2f mrad, Iact max %.3f\n',min(r.motor_position),max(r.motor_position),3.906*max(abs(r.motor_velocity)),1e3*max(abs(r.motor_position-r.load_position)),max(abs(r.motor_current_act)));
F=@(x) fft(reshape(x(1:np*P),P,np)); Uc=F(r.current_cmd); Ym=F(r.motor_position); Yl=F(r.load_position); Ua=F(r.motor_current_act);
% remove drift trend per period: position drifts -> leakage. detrend whole record linearly first
Ym=F(detrend(r.motor_position)); Yl=F(detrend(r.load_position));
e=D.exc+1; f=D.exc(:);
Um=mean(Uc(e,per),2); Hm=mean(Ym(e,per),2)./Um; Hl=mean(Yl(e,per),2)./Um; Ha=mean(Ua(e,per),2)./Um;
sm=std(Ym(e,per)./Uc(e,per),0,2)./sqrt(numel(per)); % std of mean
% nonlinear distortion: skipped odd lines and even lines vs excited output level
sk=D.skip+1; ev=(2:2:5000)+1; Ymean=mean(abs(Ym(:,per)),2);
bands=[5 20; 20 50; 50 100; 100 200; 200 400; 400 800; 800 1600; 1600 3200; 3200 5000];
for b=1:size(bands,1)
  ke=f>=bands(b,1)&f<bands(b,2); ks=D.skip(:)>=bands(b,1)&D.skip(:)<bands(b,2); kv=(2:2:5000)'>=bands(b,1)&(2:2:5000)'<bands(b,2);
  fprintf('%4d-%4d Hz: Ylevel exc %.2e skippedOdd %.2e even %.2e  | rel.std(H) %.3f\n',bands(b,:),rms(Ymean(e(ke))),rms(Ymean(sk(ks))),rms(Ymean(ev(kv))),median(sm(ke)./abs(Hm(ke))));
end
for fq=[11 31 51 101 151 201 251 301 351 401 501 1001 2001 4001]
  [~,i]=min(abs(f-fq)); w=2*pi*f(i);
  fprintf('%5d Hz |Hm| %.3e Jeq %.3e ph %7.1f | |Hl| %.3e ph %7.1f | Iact/cmd %.3f %6.1f\n',f(i),abs(Hm(i)),1/(abs(Hm(i))*w^2),angle(Hm(i))*180/pi,abs(Hl(i)),angle(Hl(i))*180/pi,abs(Ha(i)),angle(Ha(i))*180/pi);
end
save(fullfile(H,"frf_"+NAME+".mat"),'f','Hm','Hl','Ha','sm','Ts');
