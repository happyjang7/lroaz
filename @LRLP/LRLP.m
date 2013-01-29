% LRLP solves a 2 Stage Likelihood Robust Linear Program with Recourse
% (LRLP-2) via the modified Bender's Decomposition proposed by David Love.
% This class uses the LPModel class to create and store the LP data.

classdef LRLP < handle
    
%     Problem Parameters
    properties (GetAccess=public, SetAccess=immutable)
        lpModel
        gammaPrime
        numObsPerScen
        numObsTotal
        nBar
        optimizer
    end
    
%     Enumeration Parameters
    properties (GetAccess=private, SetAccess=immutable)
        LAMBDA
        MU
        THETA
        SLOPE
        INTERCEPT
    end
    
%     Bender's Decomposition Parameters
    properties (Access=private)
        candidateSolution
        bestSolution
        secondBestSolution
        zLower
        zUpper
        objectiveCutsMatrix
        objectiveCutsRHS
        feasibilityCutsMatrix
        feasibilityCutsRHS
        secondStageValues
        secondStageDuals
    end
    
%     LRLP Solution Parameters
    properties (GetAccess=public, SetAccess=private)
        pWorst
    end
    
%     Boolean parameters for the algorithm
    properties (Access=private)
        muIsFeasible
    end
    
    methods
        % LRLP Constructor checks initialization conditions and generates
        % all immutable properties for the algorithm
        function obj = LRLP( inLPModel, inGammaPrime, inNumObsPerScen, inOptimizer )
            if nargin < 1 || ~isa(inLPModel,'LPModel')
                error('LRLP must be initialized with an LPModel as its first argument')
            end
            
            obj.lpModel = inLPModel;
            
            if nargin < 4
                inOptimizer = 'linprog';
                if nargin < 3
                    inNumObsPerScen = ones(1,obj.lpModel.numScenarios);
                    if nargin < 2
                        inGammaPrime = 0.5;
                    end
                end
            end
            
            if obj.lpModel.numStages ~= 2
                error('Must use a 2 Stage LP')
            end
            if length(inNumObsPerScen) ~= obj.lpModel.numScenarios
                error('Size of observations differs from number of scenarios')
            end
            if inGammaPrime < 0 || inGammaPrime > 1
                error('Gamma Prime must be between 0 and 1')
            end
            
            obj.gammaPrime = inGammaPrime;
            obj.numObsPerScen = inNumObsPerScen;
            obj.numObsTotal = sum(obj.numObsPerScen);
            obj.nBar = obj.numObsTotal*(log(obj.numObsTotal)-1) ...
                - log(obj.gammaPrime);
            obj.optimizer = inOptimizer;
            
            obj.LAMBDA = size( obj.lpModel.A, 2 ) + 1;
            obj.MU = obj.LAMBDA + 1;
            obj.THETA = obj.MU + 1;
            
            obj.SLOPE = 1;
            obj.INTERCEPT = 2;
            
            obj.InitializeBenders();
        end
        
        % InitializeBenders initializes all Bender's Decomposition
        % parameters 
        function InitializeBenders( obj )
            obj.objectiveCutsMatrix = [];
            obj.objectiveCutsRHS = [];
            obj.feasibilityCutsMatrix = [];
            obj.feasibilityCutsRHS = [];
            obj.ResetSecondStageSolutions();
            obj.zLower = -Inf;
            obj.zUpper = Inf;
            
            % Solve first stage LP
            obj.candidateSolution = [];
            switch obj.optimizer
                case 'linprog'
                    [x0,~,exitFlag] = linprog(obj.lpModel.c, ...
                        [], [], ...
                        obj.lpModel.A, obj.lpModel.b, ...
                        obj.lpModel.l, obj.lpModel.u);
                otherwise
                    error(['Optimizer ' obj.optimizer ' is not defined'])
            end
            if exitFlag ~= 1
                error('Could not solve first stage LP')
            end
            
            obj.bestSolution = [x0; 0; 0; 0];
            obj.bestSolution(obj.LAMBDA) = 1;
            obj.bestSolution(obj.MU) = -Inf;
            obj.bestSolution(obj.THETA) = -Inf;
            
            assert( length(obj.bestSolution) == obj.THETA );
            
            obj.SolveSubProblems()
            obj.GenerateCuts()
            obj.UpdateTolerances()
        end
            
                
        % SolveMasterProblem clears candidate solution and second stage
        % information, then solves the master problem
        function SolveMasterProblem( obj )
            
        end
        
        % SolveSubProblems solves all subproblems, generates second stage
        % dual information
        function SolveSubProblems( obj )
            for scenarioNum = 1:obj.lpModel.numScenarios
                obj.SubProblem( scenarioNum );
            end
        end
        
        % GenerateCuts generates objective cut, and if necessary, generates
        % a feasibility cut and finds a good feasible value of mu
        function GenerateCuts( obj )
            if obj.Mu() <= max( obj.secondStageValues )
                obj.muIsFeasible = false;
                obj.GenerateFeasibilityCut();
                obj.FindFeasibleMu();
            else
                obj.muIsFeasible = true;
            end
            
            obj.GenerateObjectiveCut();
        end
        
        % UpdateTolerances updates the upper bound on the optimal value and
        % the objective and probability tolerances
        function UpdateTolerances( obj )
            
        end
        
    end
    
    methods (Access=private)
        % SubProblem solves an individual subproblem, updating the optimal
        % value and dual solution to the sub problem
        function SubProblem( obj, inScenNumber )
            q = obj.lpModel.Getq( inScenNumber );
            D = obj.lpModel.GetD( inScenNumber );
            d = obj.lpModel.Getd( inScenNumber );
            B = obj.lpModel.GetB( inScenNumber );
            l = obj.lpModel.Getl2( inScenNumber );
            u = obj.lpModel.Getu2( inScenNumber );
            [~,fval,~,~,pi] = linprog(q, ...
                [],[], ...
                D, d + B*obj.X(), ...
                l, u);
            
            obj.secondStageDuals{ inScenNumber, obj.SLOPE } = -pi.eqlin'*B;
            obj.secondStageDuals{ inScenNumber, obj.INTERCEPT } ...
                = - pi.eqlin'*d ...
                  - pi.upper(u<Inf)'*u(u<Inf) ...
                  - pi.lower(l~=0)'*l(l~=0);
            obj.secondStageValues( inScenNumber ) = fval;
        end
        
        % GenerateObjectiveCut generates an objective cut and adds it to
        % the matrix
        function GenerateObjectiveCut( obj )
            
        end
        
        % GenerateFeasibilityCut generates a feasibility cut and adds it to
        % the matrix
        function GenerateFeasibilityCut( obj )
            [~,hIndex] = max( obj.secondStageValues );
            
            feasSlope = [obj.secondStageDuals{hIndex,obj.SLOPE}, 0, -1, 0];
            feasInt = obj.secondStageDuals{hIndex,obj.INTERCEPT};
            
            obj.feasibilityCutsMatrix = [obj.feasibilityCutsMatrix; feasSlope];
            obj.feasibilityCutsRHS = [obj.feasibilityCutsRHS; -feasInt];
        end
        
        % FindFeasibleMu uses Newton's Method to find a feasible value of
        % mu
        function FindFeasibleMu( obj )
            [hMax hIndex] = max( obj.secondStageValues );
            mu = obj.lpModel.numScenarios/2 ...
                * obj.numObsPerScen(hIndex)*obj.Lambda() ...
                + hMax;
            
            for ii=1:200
                muOld = mu;
                mu = mu + (sum(obj.Lambda() * obj.numObsPerScen./(mu - obj.secondStageValues))-1) / ...
                    sum(obj.Lambda() * obj.numObsPerScen./((mu - obj.secondStageValues).^2));
                if abs(mu - muOld) < min(mu,muOld)*0.01
                    break
                end
            end
            obj.bestSolution( obj.MU ) = max(mu, hMax+1);
        end
        
        % ResetSecondStageSolutions clears the second stage solution values
        % and dual solution information
        function ResetSecondStageSolutions( obj )
            obj.secondStageValues = -Inf(1,obj.lpModel.numScenarios);
            obj.secondStageDuals = cell(obj.lpModel.numScenarios,2);
        end
        
    end
    
%     Accessor methods
    methods (Access=public)
        % X returns the best value of decisions x
        function outX = X( obj )
            outX = obj.bestSolution( 1:size(obj.lpModel.A,2) );
        end
        
        % Lambda returns the best value of lambda
        function outLambda = Lambda( obj )
            outLambda = obj.bestSolution( obj.LAMBDA );
        end
        
        % Mu returns the best value of mu
        function outMu = Mu( obj )
            outMu = obj.bestSolution( obj.MU );
        end
        
        % NumObjectiveCuts returns the number of objective cuts
        function outNum = NumObjectiveCuts( obj )
            outNum = size(obj.objectiveCutsMatrix,1);
        end
        
        % NumFeasibilityCuts returns the number of objective cuts
        function outNum = NumFeasibilityCuts( obj )
            outNum = size(obj.feasibilityCutsMatrix,1);
        end
        
    end
        
end