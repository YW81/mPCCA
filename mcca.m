%X  (nn x N) :  input data 1 
%Y  (mm x N) :  input data 2
%N: the number of training pairs
%d: dimension of z (after reduction)
%K: number of mixtures
% cyc - maximum number of cycles of EM (default 100)
% tol - termination tolerance (prop change in likelihood) (default 0.0001)

%x = Wx * z + Mux
%y = Wy * z + Muy


% Wx (K x nn x d): transformation matrix for x
% Wy (K x mm x d): transformation matrix for y
% Mux ((K x nn):  mean for transformation x 
% Muy ((K x mm):  mean for transformation y 
% Psix ( nn x nn x K): covariance for transformation x 
% Psiy ( mm x mm x K): covariance for transformation y 
% Wi (K x 1):  - priors

% LL - log likelihood curve

% Iterates until a proportional change < tol in the log likelihood 
% or cyc steps of EM 

function [Wx, Wy, Mux, Muy, Psix, Psiy, Wi, LL] = mcca(X, Y, d,K,cyc,tol, diagV, sharCov)
if nargin<8   sharCov=0; end; % using shared covariance matrices
if nargin<7   diagV=1; end; % using diagonal covariance matrices Psix Psiy
if nargin<6   tol=0.0001; end;
if nargin<5   cyc=100; end;
if nargin<4   K=2; end;
if nargin<3   d=1; end;

[nn, N]= size(X);
mm = size(Y, 1);

rng('default') ;

tiny=exp(-200);
LL=[];
Id=eye(d);
Ttd1 = eye(d+1)*tiny;
%innitize parameters: Wx, Wy,  Mux, Muy, Psix, Psiy, Wi
mX = mean(X, 2);
cX = cov(X');
mY = mean(Y, 2);
cY = cov(Y');

scale=exp(2*sum(log(diag(chol(cX))))/nn);
Wx=randn(K , nn , d)*sqrt(scale/d);
scale=exp(2*sum(log(diag(chol(cY))))/mm);
Wy=randn(K , mm , d)*sqrt(scale/d);
Psix = zeros( nn , nn , K);
Psiy = zeros( mm , mm , K);

for i=1:K
    Mux(i, :) = mX;
    Muy(i, :) = mY;
    Psix(:,:,i) = diag(diag(cX))+tiny;
    Psiy(:,:,i) = diag(diag(cY))+tiny;
end
Mux = Mux + randn(K, nn)*sqrtm(cX);
Muy = Muy + randn(K, mm)*sqrtm(cY);

%innitize hidden parameters
G=zeros(N, K); %posterior probabilties  p(k|x_i)
Ez = zeros(N,d,K);  % E(z_{i,k})
Ezz = zeros(d,d, K);  % E(z_{i,k}z_{i,k}')
%Vzz = zeros(d,d,K);

Vxy  = zeros(mm+nn, mm+nn, K);
Wi = ones(K,1)/K;

XY =[X; Y]';

likbase = 0;
%% EM Training of CCA
fprintf('\n Begin EN training\n');
for jj=1:cyc
    fprintf(' EM Step %d \n', jj);
    %parameters for p(v|k)

    
    Muz = [Mux, Muy];
    Pr = zeros(K, N);
    for kk=1:K
        Wxk = squeeze(Wx(kk,:,:));
        Wyk = squeeze(Wy(kk,:,:));
        Vxy(1:nn,1:nn,kk) = Wxk*Wxk' + squeeze(Psix(:,:,kk));
        Vxy(1+nn:mm+nn,1+nn:mm+nn,kk) = Wyk*Wyk' + squeeze(Psiy(:,:,kk));
        Vxy(1:nn,1+nn:mm+nn,kk) = Wxk*Wyk';
        Vxy(1+nn:mm+nn,1:nn,kk) = Wyk*Wxk';
        % test code 
%         [R,err] = cholcov(squeeze(Vxy(:,:,kk)),0);
%         if (err~=0)
%             squeeze(Vxy(:,:,kk))
%         end
		if det(Vxy(:,:,kk)) < eps
			row = sum(Vxy(:,:,kk), 2) ;
			rowSumMin = min(row) ;
			column = sum(Vxy(:,:,kk), 1) ;
			columnSumMin = min(column) ;
			addOn = max(rowSumMin, columnSumMin) ;
			if addOn < 0
				Vxy(:,:,kk) = Vxy(:,:,kk) - addOn * eye(mm+nn) ;
			end
		end
       Pr(kk, :) = mvnpdf(XY, Muz(kk,:,:), squeeze(Vxy(:,:,kk)));
    end
   

    %calculate likelihood
   
    %Pr = rprod(Pr, Wi);%size: K x N 
     sW = repmat(Wi, 1, N);
     Pr = Pr.*sW;
     clear sW;
    
    lik = sum(log(sum(Pr)));
    fprintf(' Likelihood %f (Cycle %d) \n', lik, jj);
    LL =[ LL ,lik ];
    oldlik =  likbase;
    if (jj<=1)      
      likbase=lik;
    elseif (jj<=2) 
      likbase=lik;    
    elseif (lik<oldlik) 
      fprintf(' violation');
    elseif ((lik-likbase)<(1 + tol)*(oldlik-likbase)|~isfinite(lik)) 
      break;
    end;
    
    
     % E-step: calculate hidden parameters
    
    sPr = sum(Pr, 1);
    sPr = 1./sPr;
    sPr = repmat(sPr, K ,1);
    G = sPr.*Pr;    
    G = G'; %G(i,k)=p(k|v_i) size N x K
    clear sPr Pr;
    
    % M-step:
    Wi = sum(G, 1)'/N; %calculate w_k
    if sharCov==1 
       PsixT = zeros(nn);
       PsiyT = zeros(mm);
    end
    for kk=1:K
		Wxk = squeeze(Wx(kk,:,:));
        Wyk = squeeze(Wy(kk,:,:));
        Wk = [Wxk ; Wyk];
        Pki = inv(squeeze(Vxy(1:mm+nn,1:mm+nn,kk)));
        WPik = Wk'*Pki;
        vzik = Id- WPik*Wk;%covariance for for p(z|x_i,y_i,k)
		
		Gk = G(:, kk);
        sGk = sum(Gk);
        GkM = repmat(Gk, 1, d+1);
		Gzz = zeros(d+1, d+1) ;
		
		for indexSample = 1 : N
			%% E-step %%
			zik  = WPik*[X(:, indexSample)- Mux(kk,:)'; Y(:, indexSample)- Muy(kk,:)']; %mean for p(z|x_i,y_i,k)
%            vzik = Id- WPik*Wk;%covariance for for p(z|x_i,y_i,k)
            Ez(indexSample,:,kk) = zik;
            Ezz(:,:,kk) = vzik+zik*zik'; % E((zz'|x_i,y_i,k)
			%% M-step %%
			GzzSample = zeros(d+1, d+1) ;
			GzzSample(1:d, 1:d) = Gk(indexSample) * Ezz(:,:,kk) ;
			GzzSample(1+d, 1:d) = Gk(indexSample) * Ez(indexSample, :, kk) ;
			GzzSample(1:d, 1+d) = Gk(indexSample) * Ez(indexSample, :, kk) ;
			GzzSample(1+d, 1+d) = Gk(indexSample) ;
			Gzz = Gzz + GzzSample;
		end
		%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        Ezka = [squeeze(Ez(:,:,kk)),ones(N,1)]; % N x (d+1)
        Gxz = X*(Ezka.*GkM); %  nn x (d+1)		

        Gzzi = inv(Gzz+ Ttd1);
        WMux = Gxz * Gzzi; % nn x (d+1);
 %        WMux = Gxz /(Gzz+ Ttd1);
        Wx(kk,:,:) = WMux(:, 1:d);
        Mux(kk,:) = WMux(:, 1+d);
        
        %%%begin for testing Gxz, Gzz
%         Gxzt = zeros(nn+mm, d+1);
%         Gzzt = zeros(d+1, d+1);
%         for i=1:N;
%             Gxzt = Gxzt + Gk(i,kk)*X(:,i)*Ezka(i, :);
%             Gzzt = Gzzt +Gk(i)* Ezzka(i, :, :);
%         end
        %%%end for testing Gxzt, Gzzt
        
        Gyz = Y*(Ezka.*GkM);
        WMuy = Gyz * Gzzi;
        Wy(kk,:,:) = WMuy(:, 1:d);
        Muy(kk,:) = WMuy(:, 1+d); 
        
        clear GkM GkM Gxz Gyz Gzz Gzzi ;
        GkM = repmat(Gk', nn, 1); %nn x N
        Xh = X - WMux*Ezka';  %nn x N
        
        if sharCov==0
            if diagV ==1 
                Psix(:,:,kk) = diag(diag((X.*GkM)*Xh'/sGk));%+eye(mm)*tiny
            else
                Psix(:,:,kk) = (X.*GkM)*Xh'/sGk;%+eye(mm)*tiny
            end
        else
            if diagV ==1 
                PsixT = PsixT+ diag(diag((X.*GkM)*Xh'));%+eye(mm)*tiny
            else
                PsixT = PsixT+ (X.*GkM)*Xh';%+eye(mm)*tiny
            end
        end
%         if(sum( eig(squeeze(Psix(:,:,kk)))<=0) > 0)
%             err = 2;
%         end
        clear GkM Xh;
        
        GkM = repmat(Gk', mm, 1); %mm x N
        Yh = Y - WMuy*Ezka';  %mm x N
        if sharCov==0      
            if diagV ==1 
                Psiy(:,:,kk) = diag(diag((Y.*GkM)*Yh'/sGk));%+eye(mm)*tiny
            else
                Psiy(:,:,kk) = (Y.*GkM)*Yh'/sGk;%+eye(mm)*tiny
            end
        else
            if diagV ==1 
                PsiyT = PsiyT + diag(diag((Y.*GkM)*Yh'));%+eye(mm)*tiny
            else
                PsiyT = PsiyT + (Y.*GkM)*Yh';%+eye(mm)*tiny
            end
        end
            
         %mm x mm   
%         if(sum( eig(squeeze(Psiy(:,:,kk)))<=0) > 0)
%             err = 2;
%         end         
        clear GkM Yh;
 
    end
    if sharCov==1 
       PsixT = PsixT/N;
       PsiyT = PsiyT/N;
       for kk=1:K
           Psix(:,:,kk) = PsixT;
           Psiy(:,:,kk) = PsiyT;
       end
    end
end