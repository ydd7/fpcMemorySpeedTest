unit SpeedTest;

{$mode objfpc}{$H+}
{$MODESWITCH CLASSICPROCVARS+}

interface

uses
  Classes, SysUtils, SpeedTestRT;

const
  KB = 1024;
  MB = 1024 * KB;
  GB = 1024 * MB;

type
  TMemorySpeedTest = class(TSpeedTestBase)
  const
    BUF_SIZE = 512 * MB;
  private
    FBufFrom: Pointer;
    FBufTo: Pointer;
  public
    constructor Create; override;
    destructor Destroy; override;
  published
    procedure Copy_CIC;
    procedure Read_CIC;
    procedure Write_CIC;
  end;

implementation

{ TMemorySpeedTest }

constructor TMemorySpeedTest.Create;
begin
  inherited;
  IterationCount := 5;
  OperationCountPerIteration := BUF_SIZE;
  OperationUnit := 'B';
  OperationUnitKB := 1024;

  TestsAssign([Read_CIC, Write_CIC, Copy_CIC]);
  FBufFrom := AllocMem(BUF_SIZE);
  GetMem(FBufTo, BUF_SIZE);
end;

destructor TMemorySpeedTest.Destroy;
begin
  FreeMem(FBufFrom);
  FreeMem(FBufTo);
  inherited;
end;

procedure TMemorySpeedTest.Copy_CIC;
var
  PFrom, PTo: PInt64;
  LLastP1: Pointer;
begin
  PFrom := FBufFrom;
  LLastP1 := Pointer(PtrUInt(PFrom) + BUF_SIZE);
  PTo := FBufTo;
  while (PtrUInt(PFrom) < PtrUInt(LLastP1)) do
  begin
    PTo^ := PFrom^;
    Inc(PFrom);
    Inc(PTo);
  end;
end;

procedure TMemorySpeedTest.Read_CIC;
var
  P: PInt64;
  LLastP1: Pointer;
begin
  P := FBufFrom;
  LLastP1 := Pointer(PtrUInt(P) + BUF_SIZE);
  while (PtrUInt(P) < PtrUInt(LLastP1)) do
  begin
    if (P^ = 1) then
      Abort;
    Inc(P);
  end;
end;

procedure TMemorySpeedTest.Write_CIC;
var
  P: PInt64;
  LLastP1: Pointer;
begin
  P := FBufTo;
  LLastP1 := Pointer(PtrUInt(P) + BUF_SIZE);
  while (PtrUInt(P) < PtrUInt(LLastP1)) do
  begin
    P^ := -1;
    Inc(P);
  end;
end;

initialization
  TMemorySpeedTest.Run(3);

end.
