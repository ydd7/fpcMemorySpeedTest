unit SpeedTestRT;

interface

uses
  Types, Math, Classes, SysUtils;

type
  TProcO = procedure of object;
  TArrayOfString = TStringDynArray;
  TStringCharArray      = array[1..MaxInt] of Char;
  PStringCharArray      = ^TStringCharArray;

  TBufferRec = record
    Buf: PChar;
    Len: Integer;
  end;
  PBufferRec = ^TBufferRec;

  TPerformanceCounterByDT = record
    Started: TDateTime;
    Value: TDateTime;
  end;

var
  FSpeedTestRun_BatchIndex: Integer;
type
  TSpeedTestResult_Rec = record
    Str: String;
    Buf: TBufferRec;
  end;
{$M+}
  TSpeedTestBase = class
  private
    TestCount: Integer;
    Tests: array of TProcO;
    FTestResultCur: TSpeedTestResult_Rec;

    function  TestRun_Sec(AIndex: Integer; ACIC: Boolean): Extended;
  protected
    BestTimesShow: Boolean;
    IterationCount: Integer;
    OperationCountPerIteration: Integer;
    OperationUnit: String;
    OperationUnitKB: Integer;

    procedure BatchRun_After; virtual;
    procedure BatchRun_Before; virtual;
    procedure TestRun_Before({%H-}ATestCode: Pointer); virtual;
    procedure TestResultCur_Set(AValue: String); overload; inline;
    procedure TestResultCur_Set(ABuf: PChar; ALen: Integer); overload; inline;

    procedure TestsAssign(const ATests: array of TProcO);
  public
    constructor Create; virtual;

    class procedure Run(ABatchCount: Integer);
  end;
{$M-}
  TSpeedTestBaseClass = class of TSpeedTestBase;

implementation

function  String_PCharGet(const AStr: String): PChar;
begin
  Result := PChar(PStringCharArray(AStr));
end;

function  String_PCharGet(const AStr: String; AIndex: Integer): PChar;
begin
  Result := String_PCharGet(AStr) + AIndex - 1;
end;

function  FloatToStringWithThousandthSeparator(AFloat: Extended;
  ADigitsAfterDecimalPoint: Byte; AClearFirstZero: Boolean = False): String;

begin
  Result := FloatToStrF(AFloat, ffNumber, 18, ADigitsAfterDecimalPoint);
  if AClearFirstZero and (Result[1] = '0') then
    System.Delete(Result, 1, 1);
end;

function  IntToStrWithThousandthSeparator(AValue: Int64): String;
begin
  Result := FloatToStringWithThousandthSeparator(AValue, 0);
end;

procedure StringCompareAssert(const AValue1, AValue2: String);
  procedure LError;
  begin
    raise Exception.Create('"' + AValue1 + '" <> "' + AValue2 + '"');
  end;
begin
  if (AValue1 <> AValue2) then
    LError;
end;

function  StringSuffixCheck(const S, ASuffix: String): Boolean;
var
  LSLen, LSuffixLen, LFrom: Integer;
begin
  LSLen := Length(S);
  LSuffixLen := Length(ASuffix);
  if (ASuffix = '') then
    Result := True
  else
  if (LSuffixLen > LSLen) then
    Result := False
  else
  begin
    LFrom := LSLen - LSuffixLen + 1;
    Result := CompareMem(String_PCharGet(S, LFrom), String_PCharGet(ASuffix), LSuffixLen);
  end;
end;

function  StringSuffixDeleteCheck(var S: String; const ASuffix: String): Boolean;
begin
  Result := StringSuffixCheck(S, ASuffix);
  if Result then
    SetLength(S, Length(S) - Length(ASuffix));
end;

procedure CounterClear(out APC: TPerformanceCounterByDT);
begin
  FillChar(APC{%H-}, SizeOf(APC), 0);
end;

procedure CounterStart(var APC: TPerformanceCounterByDT;
  const ADateStarted: TDateTime = 0);
begin
  if (ADateStarted = 0) then
    APC.Started := Now
  else
    APC.Started := ADateStarted;
end;

procedure CounterClearAndStart(out APC: TPerformanceCounterByDT);
begin
  CounterClear(APC);
  CounterStart(APC);
end;

procedure CounterFinish(var APC: TPerformanceCounterByDT);
begin
  APC.Value += Now - APC.Started;
end;

function  CounterSeconds(const APC: TPerformanceCounterByDT): Extended; overload;
begin
  Result := APC.Value  * 24 * 60 * 60;
end;

{ TSpeedTestBase }

constructor TSpeedTestBase.Create;
begin
  inherited;
  BestTimesShow := True;
  IterationCount := 1;
  OperationCountPerIteration := 1;
  OperationUnit := 'Op';
  OperationUnitKB := 1000;
end;

procedure TSpeedTestBase.BatchRun_After;
begin
end;

procedure TSpeedTestBase.BatchRun_Before;
begin
end;

procedure TSpeedTestBase.TestRun_Before(ATestCode: Pointer);
begin
end;

procedure TSpeedTestBase.TestResultCur_Set(AValue: String);
begin
  FTestResultCur.Str := AValue;
end;

procedure TSpeedTestBase.TestResultCur_Set(ABuf: PChar; ALen: Integer);
begin
  FTestResultCur.Buf.Buf := ABuf;
  FTestResultCur.Buf.Len := ALen;
end;

type
  TSpeedTest_Thread = class(TThread)
  private
    Test: TSpeedTestBase;
    Index: Integer;
    CIC: Boolean;
    Seconds: Extended;
  protected
    procedure Execute; override;
  public
    constructor Create(ATest: TSpeedTestBase; AIndex: Integer; ACIC: Boolean);
  end;

{ TSpeedTest_Thread }

var
  FSpeedTest_Thread_StartFlag: Boolean;

constructor TSpeedTest_Thread.Create(ATest: TSpeedTestBase; AIndex: Integer;
  ACIC: Boolean);
begin
  Test := ATest;
  Index := AIndex;
  CIC := ACIC;
  inherited Create(False);
end;

procedure TSpeedTest_Thread.Execute;
begin
  while not FSpeedTest_Thread_StartFlag do
    Sleep(1);
  Seconds := Test.TestRun_Sec(Index, CIC);
end;

type
  TSpeedTestRunHelper = class
  strict private
    A_ThreadCountMax: Integer;

    //FLogFile: Text;
    FCSVFile: Text;

    ThreadCountCur: Integer;
    Test: TSpeedTestBase;
    TestNames: TArrayOfString;
    TestCICs: array of Boolean;
    TestResult: TSpeedTestResult_Rec;
    TestResultAssigned: Boolean;
    ThreadTests: array of TSpeedTestBase;
    WorkloadKoef: Int64;
    WorkloadUnit: String;

    Seconds: array of Extended;
    SecondsMin: Extended;
    SecondsMax: Extended;
    SecondsAvg: Extended;

    procedure BatchRun_Before;
    procedure BatchRun_After;
    procedure RunInternal(ABatchCount: Integer);
    procedure TestResultsCompareAssert(const ARec1, ARec2: TSpeedTestResult_Rec);
    procedure TestRun(AIndex: Integer; ACIC: Boolean);
  public
    constructor Create(AClass: TSpeedTestBaseClass; AThreadCountMax: Integer);
    destructor Destroy; override;

    procedure Run(ABatchCount: Integer);
  end;

{ TSpeedTestRunHelper }

constructor TSpeedTestRunHelper.Create(AClass: TSpeedTestBaseClass; AThreadCountMax: Integer);
var
  i: Integer;
  DTS: String;
begin
  DTS := FormatDateTime('yymmdd_hhnnss', Now);
  //Assign(FLogFile, DTS + '.log');
  //Rewrite(FLogFile);
  //Writeln(FLogFile, 'started');

  inherited Create;

  A_ThreadCountMax := AThreadCountMax;
  //Test := AClass.Create;
  Test := AClass.Create;

  SetLength(TestNames{%H-}, Test.TestCount);
  SetLength(TestCICs, Test.TestCount);
  for i := 0 to Test.TestCount - 1 do
  begin
    TestNames[i] := Test.MethodName(TMethod(Test.Tests[i]).Code);
    TestCICs[i] := StringSuffixDeleteCheck(TestNames[i], '_CIC');//!CIC - Call In Cycle
  end;

  TestResultAssigned := False;

  SetLength(ThreadTests, AThreadCountMax + 1);
  ThreadTests[0] := Test;
  if (AThreadCountMax > 0) then
  begin
    ThreadTests[1] := Test;//!!!
    ThreadTests[AThreadCountMax] := Test;//!!!
    FillChar(ThreadTests[1], AThreadCountMax * SizeOf(ThreadTests[1]), #0);
    Assert(not Assigned(ThreadTests[1]));
    Assert(not Assigned(ThreadTests[AThreadCountMax]));
  end;
  SetLength(Seconds, AThreadCountMax + 1);

  Assign(FCSVFile, DTS + '.csv');
  Rewrite(FCSVFile);
end;

destructor TSpeedTestRunHelper.Destroy;
var
  i: Integer;
begin
  for i := 0 to Length(ThreadTests) - 1 do
    FreeAndNil(ThreadTests[i]);
  Close(FCSVFile);
  //Close(FLogFile);
  inherited;
end;

procedure TSpeedTestRunHelper.BatchRun_Before;
var
  i: Integer;
begin
  for i := 0 to ThreadCountCur do
    ThreadTests[i].BatchRun_Before;
end;

procedure TSpeedTestRunHelper.BatchRun_After;
var
  i: Integer;
begin
  for i := 0 to ThreadCountCur do
    ThreadTests[i].BatchRun_After;
end;

procedure TSpeedTestRunHelper.TestResultsCompareAssert(const ARec1, ARec2: TSpeedTestResult_Rec);
  function  LToS(const ARec: TSpeedTestResult_Rec): String;
  begin
    if (ARec.Str <> '') then
    begin
      Assert(not Assigned(ARec.Buf.Buf));
      Assert(ARec.Buf.Len = 0);
      Result := ARec.Str;
    end
    else
      SetString(Result, ARec.Buf.Buf, ARec.Buf.Len);
  end;
begin
  StringCompareAssert(LToS(ARec1), LToS(ARec2));
end;

procedure TSpeedTestRunHelper.TestRun(AIndex: Integer; ACIC: Boolean);
var
  i: Integer;
  LThreads: array of TSpeedTest_Thread;
begin
  SetLength(LThreads, ThreadCountCur + 1);
  try
    FSpeedTest_Thread_StartFlag := False;
    for i := 1 to ThreadCountCur do
      LThreads[i] := TSpeedTest_Thread.Create(ThreadTests[i], AIndex, ACIC);

    FSpeedTest_Thread_StartFlag := True;
    Sleep(1);
    Seconds[0] := Test.TestRun_Sec(AIndex, ACIC);
    for i := 1 to ThreadCountCur do
      LThreads[i].WaitFor;

    if TestResultAssigned then
      TestResultsCompareAssert(TestResult, Test.FTestResultCur)
    else
    begin
      TestResultAssigned := True;
      TestResult := Test.FTestResultCur;
    end;

    SecondsMin := Seconds[0];
    SecondsMax := Seconds[0];
    SecondsAvg := Seconds[0];

    for i := 1 to ThreadCountCur do
    begin
      TestResultsCompareAssert(TestResult, LThreads[i].Test.FTestResultCur);
      Seconds[i] := LThreads[i].Seconds;

      if (SecondsMin > Seconds[i]) then
        SecondsMin := Seconds[i];
      if (SecondsMax < Seconds[i]) then
        SecondsMax := Seconds[i];
      SecondsAvg := SecondsAvg + Seconds[i];
    end;
    SecondsAvg := SecondsAvg / (ThreadCountCur + 1);
  finally
    for i := 1 to ThreadCountCur do
      FreeAndNil(LThreads[i]);
  end;
end;

procedure TSpeedTestRunHelper.Run(ABatchCount: Integer);
var
  S: String;
begin
  S := Test.ClassType.ClassName;

  ThreadCountCur := 0;
  while ThreadCountCur <= A_ThreadCountMax do
  begin
    if (ThreadCountCur > 0) then
      ThreadTests[ThreadCountCur] := TSpeedTestBaseClass(Test.ClassType).Create;
    RunInternal(ABatchCount);

    Inc(ThreadCountCur);
  end;
end;

procedure TSpeedTestRunHelper.RunInternal(ABatchCount: Integer);
  procedure LWorkloadFormatInit(AOperationCount: Int64;
    out AWorkloadKoef: Int64; out AWorkloadUnit: String);
  begin
    if (AOperationCount < Test.OperationUnitKB) then
    begin
      AWorkloadKoef := 1;
      AWorkloadUnit := '';
    end
    else
    if (AOperationCount < Test.OperationUnitKB * Test.OperationUnitKB) then
    begin
      AWorkloadKoef := Test.OperationUnitKB;
      AWorkloadUnit := 'K';
    end
    else
    if (AOperationCount < Test.OperationUnitKB * Test.OperationUnitKB * Test.OperationUnitKB) then
    begin
      AWorkloadKoef := Test.OperationUnitKB * Test.OperationUnitKB;
      AWorkloadUnit := 'M';
    end
    else
    begin
      AWorkloadKoef := Test.OperationUnitKB * Test.OperationUnitKB * Test.OperationUnitKB;
      AWorkloadUnit := 'G';
    end;
    AWorkloadUnit := ' ' + AWorkloadUnit + Test.OperationUnit + 's';
  end;

const
  LMinTestExecutionTimeLength = 7;
var
  iTest, LTC, LMaxNameLen, iThread, LLen: Integer;
  LOperationCount, LWorkloadKoef: Int64;
  LWorkloadUnit: String;
  LSecondsMin, LSecondsMax, LSecondsMinAvg: array of Extended;
  LPerformance: Extended;
  LPerformanceS, LPerformanceThS: String;
  LPerformanceThSs: array of String;
begin
  LTC := Test.TestCount;
  LMaxNameLen := 0;
  SetLength(LSecondsMin{%H-}, LTC);
  SetLength(LSecondsMax{%H-}, LTC);
  SetLength(LSecondsMinAvg{%H-}, LTC);
  for iTest := 0 to LTC - 1 do
  begin
    if LMaxNameLen < Length(TestNames[iTest]) then
      LMaxNameLen := Length(TestNames[iTest]);

    LSecondsMin[iTest] := MaxDouble;
    LSecondsMax[iTest] := 0;
    LSecondsMinAvg[iTest] := MaxDouble;
  end;

  Writeln(Copy(String(Test.ClassName), 2));

  Write('  iterations: ' + IntToStrWithThousandthSeparator(Test.IterationCount));

  LWorkloadFormatInit(Test.OperationCountPerIteration, LWorkloadKoef, LWorkloadUnit);
  Write(
    ', workload / iteration: ',
    FloatToStringWithThousandthSeparator(Test.OperationCountPerIteration / LWorkloadKoef, 3),
    LWorkloadUnit
  );

  Writeln;

  if (ThreadCountCur > 0) then
  begin
    Write('  threads: ', (ThreadCountCur + 1));

    LOperationCount := Test.IterationCount * Test.OperationCountPerIteration;
    LWorkloadFormatInit(LOperationCount, LWorkloadKoef, LWorkloadUnit);
    Write(
      ', workload / thread: ',
      FloatToStringWithThousandthSeparator(LOperationCount / LWorkloadKoef, 3),
      LWorkloadUnit
    );

    Writeln;
  end;

  LOperationCount := Test.IterationCount * Test.OperationCountPerIteration * (ThreadCountCur + 1);
  LWorkloadFormatInit(LOperationCount, LWorkloadKoef, LWorkloadUnit);
  Write(
    '  total workload: ',
    FloatToStringWithThousandthSeparator(LOperationCount / LWorkloadKoef, 3),
    LWorkloadUnit
  );

  Writeln(' {');

  Write('      ');
  for iTest := 0 to LTC - 1 do
    Write(' ', '':LMinTestExecutionTimeLength - Length(TestNames[iTest]) - 1, TestNames[iTest]);

  Writeln;
{$WARNINGS OFF}
  for FSpeedTestRun_BatchIndex := 0 to ABatchCount - 1 do
{$WARNINGS ON}
  begin
    Write('  #', IntToStr(FSpeedTestRun_BatchIndex), ': ');
    BatchRun_Before;

    for iTest := 0 to LTC - 1 do
    begin
      TestRun(iTest, TestCICs[iTest]);

      LLen := Max(LMinTestExecutionTimeLength - Length(TestNames[iTest]) - 1, 0) + Length(TestNames[iTest]) + 1;
      Write(Seconds[0]:LLen:3);
      if LSecondsMin[iTest] > SecondsMin then
        LSecondsMin[iTest] := SecondsMin;
      if LSecondsMax[iTest] < SecondsMax then
        LSecondsMax[iTest] := SecondsMax;
      if LSecondsMinAvg[iTest] > SecondsAvg then
        LSecondsMinAvg[iTest] := SecondsAvg;

      if (ThreadCountCur > 0) then
      begin
        Write('(');
        for iThread := 1 to ThreadCountCur do
        begin
          if (iThread > 1) then
            Write(',');
          Write(Seconds[iThread]:6:3);
        end;
        Write(')');
      end;
    end;

    BatchRun_After;
    Writeln;
  end;

  if (ABatchCount > 1) and Test.BestTimesShow then
  begin
    if (LMaxNameLen < Length('Best times') - 2) then
      LMaxNameLen := Length('Best times') - 2;
    Write('  Best times', '':LMaxNameLen - 8, ': MinAvg (-  Min / +  Max) Performance/sec     Performance/thread');
    Writeln;
      if (WorkloadKoef = 0) then
    begin
        LWorkloadFormatInit(Round(LOperationCount / LSecondsMinAvg[iTest]),
          WorkloadKoef, WorkloadUnit
        );
      Write(FCSVFile, 'Threads');
      for iTest := 0 to LTC - 1 do
        Write(FCSVFile, ',"', TestNames[iTest], ' ', WorkloadUnit, '"');
      for iTest := 0 to LTC - 1 do
        Write(FCSVFile, ',"', TestNames[iTest], '/Th ', WorkloadUnit, '"');
      Writeln(FCSVFile);
    end;

    SetLength(LPerformanceThSs, LTC);
    Write(FCSVFile, '"', ThreadCountCur + 1, '"');
    for iTest := 0 to LTC - 1 do
    begin
      LPerformance := LOperationCount / WorkloadKoef / LSecondsMinAvg[iTest];
      LPerformanceS := FloatToStringWithThousandthSeparator(LPerformance, 3);
      LPerformanceThS := FloatToStringWithThousandthSeparator(LPerformance / (ThreadCountCur + 1), 3);
      LPerformanceThSs[iTest] := LPerformanceThS;
      Write(
        '    ',
        TestNames[iTest],
        '':LMaxNameLen - Length(TestNames[iTest]),
        ': ',
        LSecondsMinAvg[iTest]:6:3,
        ' (-',
        (LSecondsMinAvg[iTest] - LSecondsMin[iTest]):5:3,
        ' / +',
        (LSecondsMax[iTest] - LSecondsMinAvg[iTest]):5:3,
        ') ',
        LPerformanceS:11,
        WorkloadUnit,
        LPerformanceThS:19,
        WorkloadUnit
      );

      Write(FCSVFile, ',"', LPerformanceS, '"');

      Writeln;
    end;
    for iTest := 0 to LTC - 1 do
      Write(FCSVFile, ',"', LPerformanceThSs[iTest], '"');

    Writeln(FCSVFile);
    Flush(FCSVFile);
  end;
  Writeln('}');
end;

class procedure TSpeedTestBase.Run(ABatchCount: Integer);
var
  LHelper: TSpeedTestRunHelper;
begin
  LHelper := TSpeedTestRunHelper.Create(Self, StrToIntDef(ParamStr(1), 1) - 1);
  try
    LHelper.Run(ABatchCount);
  finally
    FreeAndNil(LHelper);
  end;
end;

procedure TSpeedTestBase.TestsAssign(const ATests: array of TProcO);
var
  i: Integer;
begin
  Assert(TestCount = 0);
  TestCount := Length(ATests);
  SetLength(Tests, TestCount);
  for i := 0 to TestCount - 1 do
    Tests[i] := ATests[i];
end;

function  TSpeedTestBase.TestRun_Sec(AIndex: Integer; ACIC: Boolean): Extended;
var
  i: Integer;
  LTest: TProcO;
  LCounter: TPerformanceCounterByDT;//TPerformanceCounterByST;
begin
  LTest := Tests[AIndex];
  FTestResultCur.Str := '';
  FTestResultCur.Buf.Buf := Nil;
  FTestResultCur.Buf.Len := 0;
  TestRun_Before(TMethod(LTest).Code);

  CounterClearAndStart(LCounter);
  if ACIC then
    for i := 1 to IterationCount do
      LTest
  else
    LTest;
  CounterFinish(LCounter);
  Result := CounterSeconds(LCounter);
end;

end.
