function data = PlotSolveTime( varargin )
%PlotSolveTime Plot time required to solve a phi-divergence problem vs
%number of scenarios
%
% Keyword arguments:
%    lp: LPModel object
%    phi: PhiDivergence object or string type of phi-divergence
%    scens: vector giving number of scenarios to time solution against

if mod(length(varargin),2) == 1
    error('Arguments must be key, value pairs')
end

for vv = 1:2:length(varargin)
    key = varargin{vv};
    value = varargin{vv+1};
    switch key
        case 'lp'
            lp = value;
        case 'phi'
            if isa(value, 'PhiDivergence')
                phi = value;
            elseif ischar(value)
                phi = PhiDivergence( value );
            else
                error('Phi must be PhiDivergence object or string')
            end
        case 'scens'
            scens = value;
        otherwise
            error(['Unknown variable ', key])
    end
end

data = struct;

for ii = 1:length(scens)
    lpPruned = PruneScenarios( lp, 1:scens(ii) );
    obs = ones(1,scens(ii));
    
    timeStart = tic;
    [solvedLRLP,c1,n1] = SolveLRLP( lpPruned, phi, obs, -1 );
    timeIndiv = toc(timeStart);
    
    x1 = solvedLRLP.bestSolution.X;
    m1 = solvedLRLP.bestSolution.Mu;
    l1 = solvedLRLP.bestSolution.Lambda;
    r1 = solvedLRLP.calculatedDivergence;
    z1 = solvedLRLP.ObjectiveValue;
    
    if ii==1
        data.scens = scens;
        data.x = zeros(length(x1),length(scens));
        data.lambda = zeros(length(l1),length(scens));
        data.mu = zeros(length(m1),length(scens));
        data.objVals = zeros(length(z1),length(scens));
        data.calcRho = zeros(length(r1),length(scens));
        data.numProbs = zeros(1,length(scens));
        data.numCuts = zeros(1,length(scens));
        data.timeRuns = zeros(1,length(scens));
    end
    
    data.x(:,ii) = x1;
    data.lambda(:,ii) = l1;
    data.mu(:,ii) = m1;
    data.objVals(:,ii) = z1;
    data.calcRho(:,ii) = r1;
    data.numProbs(ii) = n1;
    data.numCuts(ii) = c1;
    data.timeRuns(ii) = timeIndiv;
end

plot(data.scens, data.timeRuns, 'o', 'MarkerSize',10)
xlabel( 'N', 'FontSize',16 )
ylabel( 'Solution Time', 'FontSize',16)

end

