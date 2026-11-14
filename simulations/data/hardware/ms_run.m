% random-odd multisine, period 1 s, lines 5..2500 Hz. workspace: AMP, NAME, SEED
Ts=1.25e-4; P=8000; rng(SEED); kmax=2500; odd=1:2:kmax; odd=odd(odd>=5);
grp=reshape(odd(1:floor(numel(odd)/3)*3),3,[]); skip=grp(sub2ind(size(grp),randi(3,1,size(grp,2)),1:size(grp,2)));
exc=setdiff(odd,skip); U=zeros(P,1); U(exc+1)=exp(1j*2*pi*rand(numel(exc),1)); u=real(ifft(U))*P;
for it=1:30, u=sign(u).*min(abs(u),0.8*max(abs(u))); X=fft(u); X(setdiff(1:P,exc+1))=0; X(exc+1)=exp(1j*angle(X(exc+1))); u=real(ifft(X)); end
u=AMP*u/max(abs(u)); FF=u; REPEAT=14; REF=zeros(size(FF));
save(fullfile('C:/Users/Nogiku/AppData/Local/Temp/claude/163a9fc9a304703e/67da9375-757e-4d7c-8f6c-2a0d19d37214/scratchpad/hw',NAME+"_design.mat"),'exc','skip','u');
fprintf('crest %.2f rms %.4f\n', max(abs(u))/rms(u), rms(u));
addpath('c:/Users/Nogiku/source/repos/ExperimentHailMary/ExperimentHailMary/matlab'); CTRL=experiment.ControllerConfig.p_only(0);
run('C:/Users/Nogiku/AppData/Local/Temp/claude/163a9fc9a304703e/67da9375-757e-4d7c-8f6c-2a0d19d37214/scratchpad/hw_run.m');
