function [coef,stats,orig] = permtest_corr(x,y,varargin)
%permtest_corr permutation-based correlation with max statistic correction
%   COEF = permtest_corr(X,Y) returns the pairwise correlation coefficient
%   of a permutation test based on Pearson's correlation coefficient or
%   using a rankit (Bliss, 1967) or Spearman's rank-order transformation
%   (Bishara & Hittner, 2012). If X and Y are matrices, multiple
%   permutation tests are performed simultaneously between each
%   corresponding pair of columns in X and Y and family-wise error rate is
%   controlled using the max statistic correction method (Blair et al.,
%   1994). If Y is not entered, the correlation between each pair of
%   columns in X is computed and output as a correlation matrix. This
%   function treats NaNs as missing values, and ignores them.
%
%   [...,STATS] = permtest_corr(...) returns the adjusted test statistics
%   in a structure containing the following fields:
%       p       the probability of observing the given result by chance
%       ci    	100*(1-ALPHA)% confidence interval for each coefficient -
%               for Pearson and Rankit type correlations, the Fisher z'
%               method is used (Fisher, 1958) and for Spearman rank-order
%               correlations the method by Fieller et al. (1957) is used as
%               suggested in Bishara & Hittner (2017)
%       rcrit 	critical r-value for the given alpha level (for two-tailed
%               tests, the lower t-value is equal to -1*RCRIT)
%       estal 	the estimated alpha level of each test
%
%   [...,ORIG] = permtest_corr(...) returns the original, unadjusted test
%   statistics in a structure containing the same fields as STATS.
%
%   [...] = permtest_corr(...,'PARAM1',VAL1,'PARAM2',VAL2,...) specifies
%   additional parameters and their values. Valid parameters are the
%   following:
%
%   Parameter   Value
%   'alpha'     a scalar between 0 and 1 specifying the significance level
%               as 100*ALPHA% (default=0.05)
%   'nperm'     a scalar specifying the number of permutations (default=
%               10,000 or all possible permutations for less than 14 obs.)
%   'tail'      string specifying the alternative hypothesis
%                   'both'  correlation is not zero (default)
%                   'right' correlation is greater than zero
%                   'left'  correlation is less than zero
%   'rows'      a string specifying the rows to use in the case of any
%               missing values (NaNs)
%                   'all'       use all rows, regardless of NaNs (default)
%                   'complete'  use only rows with no NaNs
%   'type'      string specifying the type of correlation measure
%                   'Pearson'   Pearson's correlation coefficient (default)
%                   'Rankit'    Bliss's rankit correlation coefficient
%                   'Spearman'  Spearman's rank correlation coefficient
%
%   Example 1: generate multivariate data for 2 conditions, each with 20
%   variables and 30 observations and calculate the correlation between the
%   corresponding variables of each condition.
%       x = randn(30,20);
%       y = randn(30,20);
%       y(:,1:5) = y(:,1:5)+0.5*x(:,1:5);
%       y(:,15:20) = y(:,15:20)-x(:,15:20);
%       [coef,stats] = permtest_corr(x,y)
%
%   Example 2: generate univariate data for 5 conditions, each with 1
%   variable and 30 observations and calculate the correlation between
%   every pair of conditions (5 conditions = 10 correlations).
%       x = randn(30,5);
%       x(:,1:2) = x(:,1:2)-0.5*x(:,4:5);
%       [coef,stats] = permtest_corr(x)
%
%   See also PERMTEST_T PERMTEST_T2 PERMTEST_F EFFECTSIZE_D.
%
%   StatsTools https://github.com/mickcrosse/PERMUTOOLS

%   References:
%       [1] Bishara AJ, Hittner JB, (2012) Testing the Significance of a
%           Correlation With Nonnormal Data: Comparison of Pearson,
%           Spearman, Transformation, and Resampling Approaches. Psychol
%           Methods, 17(3):399-417.
%       [2] Bliss CI (1967) Statistics in biology. New York: McGraw-Hill.
%       [3] Blair RC, Higgins JJ, Karniski W, Kromrey JD (1994) A Study of
%           Multivariate Permutation Tests Which May Replace Hotelling's T2
%           Test in Prescribed Circumstances. Multivariate Behav Res,
%           29(2):141-163.
%       [4] Fisher RA (1958) Statistical Methods for Research Workers, 13th
%           ed., Hafner.
%       [5] Fieller EC, Hartley HO, Pearson ES (1957) Tests for Rank
%           Correlation Coefficients. I. Biometrika, 44(3/4):470-481.

%   Author: Mick Crosse
%   Email: mickcrosse@gmail.com
%   Cognitive Neurophysiology Laboratory,
%   Albert Einstein College of Medicine, NY
%   Jan 2018; Last Revision: 18-Jan-2019

% Decode input variable arguments
[alpha,nperm,tail,rows,type] = decode_varargin(varargin);

% Set up permutation test
mat = false;
if nargin<2 || isempty(y)
    mat = true;
    warning('Comparing all columns of X and creating correlation matrix...')
    [x,y] = paircols(x); tail = 'both';
elseif ~isnumeric(y)
    error('Y must be numeric or empty.')
elseif size(y)~=size(x)
    error('X and Y must be the same size.')
end

% Use only rows with no NaN values if specified
if strcmpi(rows,'complete')
    x = x(~any(isnan(y),2),:);
    y = y(~any(isnan(y),2),:);
    y = y(~any(isnan(x),2),:);
    x = x(~any(isnan(x),2),:);
elseif strcmpi(rows,'all') && (any(any(isnan(x))) || any(any(isnan(y))))
    error('X or Y is missing values. Set argument ROWS to ''complete''.')
end

% Get data dimensions
[nobs,nvar] = size(x);

% Transform raw data to rank-orders if specified
if strcmpi(type,'Rankit')
    x = tiedrank(x);
    y = tiedrank(y);
    x = norminv((x-0.5)/nobs);
    y = norminv((y-0.5)/nobs);
elseif strcmpi(type,'Spearman')
    x = tiedrank(x);
    y = tiedrank(y);
end

% Compute correlation coefficient
muxy = sum(x).*sum(y)/nobs;
sdxy = sqrt((sum(x.^2)-(sum(x).^2)/nobs).*(sum(y.^2)-(sum(y).^2)/nobs));
coef = (sum(x.*y)-muxy)./sdxy;

% Execute if user requests adjusted test statistics
if nargout > 1
    
    % Permute data and generate distribution of r-values
    if nobs < 8
        fprintf('Calculating all possible permutations because of small N.\n')
        nperm = factorial(nobs);
        idx = perms(1:nobs)';
    else
        [~,idx] = sort(rand(nobs,nperm));
    end
    rp = zeros(nperm,nvar);
    for i = 1:nperm
        rp(i,:) = (sum(x(idx(:,i),:).*y)-muxy)./sdxy;
    end
    
    % Compute adjusted test statistics using max statistic correction
    if strcmpi(tail,'both')
        [~,idx] = max(abs(rp),[],2);
        csvar = [0;cumsum(ones(nperm-1,1)*nvar)];
        rmax = rp'; rmax = rmax(idx+csvar);
        p = zeros(1,nvar);
        if nvar>1
            p(coef>0) = mean(coef(coef>0)<rmax)*2;
            p(coef<=0) = mean(coef(coef<=0)>rmax)*2;
        else
            rmax = rmax';
            p(coef>0) = mean(coef<rmax)*2;
            p(coef<=0) = mean(coef>rmax)*2;
        end
        rcrit(1) = prctile(rmax,100*alpha/2);
        rcrit(2) = prctile(rmax,100*(1-alpha/2));
        zci = [norminv(alpha/2);norminv(1-alpha/2)];
        estal = mean(rcrit(1)>rmax)+mean(rcrit(2)<rmax);
    elseif strcmpi(tail,'right')
        rmax = max(rp,[],2);
        p = mean(coef<rmax);
        rcrit = prctile(rmax,100*(1-alpha));
        zci = [norminv(alpha);Inf(1,nvar)];
        estal = mean(rcrit<rmax);
    elseif strcmpi(tail,'left')
        rmax = min(rp,[],2);
        p = mean(coef>rmax);
        rcrit = prctile(rmax,100*alpha);
        zci = [-Inf(1,nvar);norminv(1-alpha)];
        estal = mean(rcrit>rmax);
    end
    p(isnan(rcrit)) = NaN;
    
    % Compute confidence intervals
    zr = log((1+coef)./(1-coef))/2;
    if strcmpi(type,'Spearman')
        zci = zr+zci*sqrt(1.06/(nobs-3));
    else
        zci = zr+zci/sqrt(nobs-3);
    end
    ci = (exp(2*zci)-1)./(exp(2*zci)+1);
    
    % Arrange test results in a matrix if specified
    if mat==true
        p = statmat(p);
        ciLwr = statmat(ci(1,:));
        ciUpr = statmat(ci(2,:));
        ci = cat(3,ciLwr,ciUpr);
        ci = permute(ci,[3,1,2]);
    end
    
    % Store values in structure
    stats = struct('p',p,'ci',ci,'rcrit',rcrit,'estal',estal);
    
end

% Execute if user requests unadjusted test statistics
if nargout > 2
    
    % Clear variables
    clear p rcrit ciLwr ciUpr ci estal
    
    % Compute unadjusted test statistics
    if strcmpi(tail,'both')
        p = zeros(1,nvar);
        if nvar>1
            p(coef>0) = mean(coef(coef>0)<rmax)*2;
            p(coef<=0) = mean(coef(coef<=0)>rmax)*2;
        else
            rmax = rmax';
            p(coef>0) = mean(coef<rmax)*2;
            p(coef<=0) = mean(coef>rmax)*2;
        end
        rcrit(1,:) = prctile(rp,100*alpha/2);
        rcrit(2,:) = prctile(rp,100-100*alpha/2);
        zci = [norminv(alpha/2);norminv(1-alpha/2)];
        estal = mean(rcrit(2,:)<rp)+mean(rcrit(1,:)>rp);
    elseif strcmpi(tail,'right')
        p = mean(coef<rp);
        rcrit = prctile(rp,100*(1-alpha));
        zci = [norminv(alpha);Inf(1,nvar)];
        estal = mean(rcrit<rp);
    elseif strcmpi(tail,'left')
        p = mean(coef>rp);
        rcrit = prctile(rp,100*alpha);
        zci = [-Inf(1,nvar);norminv(1-alpha)];
        estal = mean(rcrit>rp);
    end
    p(isnan(rcrit(1,:))) = NaN;
    
    % Compute confidence intervals
    zr = log((1+coef)./(1-coef))/2;
    if strcmpi(type,'Spearman')
        zci = zr+zci*sqrt(1.06/(nobs-3));
    else
        zci = zr+zci/sqrt(nobs-3);
    end
    ci = (exp(2*zci)-1)./(exp(2*zci)+1);
    
    % Arrange test results in a matrix if specified
    if mat==true
        p = statmat(p);
        rcrit = statmat(rcrit);
        ciLwr = statmat(ci(1,:));
        ciUpr = statmat(ci(2,:));
        ci = cat(3,ciLwr,ciUpr);
        ci = permute(ci,[3,1,2]);
        estal = statmat(estal);
    end
    
    % Store values in structure
    orig = struct('p',p,'ci',ci,'rcrit',rcrit,'estal',estal);
    
end

% Arrange r-values in a matrix if specified
if mat==true
    coef = statmat(coef);
end

function [y1,y2] = paircols(x)
%paircols pair matrix columns and output as two separate matrices

% Get matrix dimensions
[nobs,nvar] = size(x);

% Preallocate memory
y1 = zeros(nobs,(nvar^2-nvar)/2);
y2 = zeros(nobs,(nvar^2-nvar)/2);

% Initialize counters
ctr = 1;
jctr = 2;

% Generate paired matrices
for i = 1:nvar
    j = jctr;
    while j <= nvar
        y1(:,ctr) = x(:,i);
        y2(:,ctr) = x(:,j);
        j = j+1;
        ctr = ctr+1;
    end
    jctr = jctr+1;
end

function [y] = statmat(x)
%statmat generate a matrix of the test statistics between all variables

% Compute matrix dimensions
nvar = ceil(sqrt(length(x)*2));

% Preallocate memory
y = NaN(nvar,nvar);

% Initialize counters
ctr = 1;
jctr = 2;

% Generate matrix
for i = 1:nvar
    j = jctr;
    while j <= nvar
        y(i,j) = x(ctr);
        y(j,i) = x(ctr);
        j = j+1;
        ctr = ctr+1;
    end
    jctr = jctr+1;
end

function [alpha,nperm,tail,rows,type] = decode_varargin(varargin)
% decode_varargin decode input variable arguments
varargin = varargin{1,1};
if any(strcmpi(varargin,'alpha')) && ~isempty(varargin{find(strcmpi(varargin,'alpha'))+1})
    alpha = varargin{find(strcmpi(varargin,'alpha'))+1};
    if ~isscalar(alpha) || ~isnumeric(alpha) || isnan(alpha) || alpha<=0 || alpha>=1
        error('ALPHA must be a scalar between 0 and 1.')
    end
else
    alpha = 0.05;
end
if any(strcmpi(varargin,'nperm')) && ~isempty(varargin{find(strcmpi(varargin,'nperm'))+1})
    nperm = varargin{find(strcmpi(varargin,'nperm'))+1};
    if ~isscalar(nperm) || ~isnumeric(nperm) || isnan(nperm) || isinf(nperm) || floor(nperm)~=nperm || nperm<=0
        error('NPERM must be a positive integer.')
    elseif (nperm<1e3 && alpha<=0.05) || (nperm<5e3 && alpha<=0.01)
        warning('Number of permutations may be too low for chosen ALPHA.')
    end
else
    nperm = 1e4;
end
if any(strcmpi(varargin,'tail')) && ~isempty(varargin{find(strcmpi(varargin,'tail'))+1})
    tail = varargin{find(strcmpi(varargin,'tail'))+1};
    if ~any(strcmpi(tail,{'left','both','right'}))
        error('Invalid value for argument TAIL. Valid values are: ''left'', ''both'', ''right''.')
    end
else
    tail = 'both';
end
if any(strcmpi(varargin,'rows')) && ~isempty(varargin{find(strcmpi(varargin,'rows'))+1})
    rows = varargin{find(strcmpi(varargin,'rows'))+1};
    if ~any(strcmpi(rows,{'all','complete'}))
        error('Invalid value for argument ROWS. Valid values are: ''all'', ''complete''.')
    end
else
    rows = 'all';
end
if any(strcmpi(varargin,'type')) && ~isempty(varargin{find(strcmpi(varargin,'type'))+1})
    type = varargin{find(strcmpi(varargin,'type'))+1};
    if ~any(strcmpi(type,{'Pearson','Spearman'}))
        error('Invalid value for argument TYPE. Valid values are: ''Pearson'', ''Spearman''.')
    end
else
    type = 'Pearson';
end