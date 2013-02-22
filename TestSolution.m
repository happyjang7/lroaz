function TestSolution()

lp = InitializeSimpleTwoStageLP;
s = Solution(lp,'multi');

% Size errors for all variables
assertExceptionThrown( @() s.SetX(zeros(size(lp.A,2)+1,1)), ...
    'Solution:SetX:size')
assertExceptionThrown( @() s.SetLambda([1 1]), 'Solution:SetLambda:size' )
assertExceptionThrown( @() s.SetMu([1 1]), 'Solution:SetMu:size' )
assertExceptionThrown( @() s.SetTheta(zeros(lp.numScenarios-1,1),'master'), ...
    'Solution:SetTheta:size' )

% Sign error for lambda
assertExceptionThrown( @() s.SetLambda(-2), 'Solution:SetLambda:sign' )

% Only master and true for theta
assertExceptionThrown( @() s.SetTheta(rand(1,lp.numScenarios),'blah'), ...
    'Solution:SetTheta:type' )

% Assign legitimate variables

s.SetX(0.5);
s.SetLambda(3);
s.SetMu(-2);
s.SetTheta(zeros(1,lp.numScenarios),'master');