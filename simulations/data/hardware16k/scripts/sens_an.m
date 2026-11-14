H='c:/Users/Nogiku/source/repos/ExperimentHailMary/ExperimentHailMary/simulations/data/hardware16k/runs';
for n=["sens_linear","sens_both"]
 R=load(fullfile(H,n+".mat")); D=load(fullfile(H,n+"_dist.mat")); r=structfun(@double,R.raw,'UniformOutput',false); P=D.P;
 np=floor(numel(r.current_cmd)/P); per=2:np; F=@(x) fft(reshape(x(1:np*P),P,np)); I=F(r.current_cmd); Dd=F(r.dist_value);
 e=D.k+1; Sx=mean(I(e,per),2)./mean(Dd(e,per),2); f=D.k;
 fprintf('%s: velocity mean %.2f rad/s (true), |S|max %.2f at %d Hz\n', n, 3.906*mean(r.motor_velocity(round(end/3):end)), max(abs(Sx)), f(find(abs(Sx)==max(abs(Sx)),1)));
 for fq=[11 21 41 61 81 101 151 201 251 301 401 601 901], [~,i]=min(abs(f-fq)); fprintf('  %4d Hz |S| %.2f\n',f(i),abs(Sx(i))); end
 save(fullfile(H,"S_"+n+".mat"),'f','Sx');
end
