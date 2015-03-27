unit main;

{$MODE OBJFPC}
{$LONGSTRINGS ON}

interface

uses
  SysUtils,
  Forms, Dialogs, Controls, ComCtrls, StdCtrls, ExtCtrls,
  DBGrids, db, SQLdb, IBConnection, Classes;

const
  EOLN = #13#10;
  STD_LOGIN = 'SYSDBA';
  STD_PASSWORD = 'masterkey';

type
  
  { TMainForm }

  TMainForm = class(TForm)
  { interface controls }
    HalfPanel1              : TPanel;
      LDatabase             : TLabel;
      DBNameEdit            : TEdit;
      LLogin                : TLabel;
      LoginEdit             : TEdit;
      LPassword             : TLabel;
      PasswordEdit          : TEdit;
      BrowseBtn             : TButton;
      ConnectBtn            : TButton;
      ExecuteBtn            : TButton;
      CommitBtn             : TButton;
      RollbackBtn           : TButton;
      DMLTgBtn              : TToggleBox;
      SQLMemo               : TMemo;

    HalfPanel2              : TPanel;
      PageControl           : TPageControl;
        LogTab              : TTabSheet;
          LogMemo           : TMemo;
        DataTab             : TTabSheet;
          DataGrid          : TDBGrid;

    Splitter                : TSplitter;
    StatusBar               : TStatusBar;
    OpenDialog              : TOpenDialog;
  { end of interface controls }

  { database controls }
    DBConnection            : TIBConnection;
    DataSource              : TDataSource;
    SQLTransaction          : TSQLTransaction;
    SQLQuery                : TSQLQuery;
  { end of database controls }

    procedure FormCreate(Sender: TObject);

    procedure BrowseBtnClick(Sender: TObject);
    procedure ConnectBtnClick(Sender: TObject);
    procedure ExecuteBtnClick(Sender: TObject);
    procedure CommitBtnClick(Sender: TObject);
    procedure RollbackBtnClick(Sender: TObject);

    procedure DBConnectionAfterConnect(Sender: TObject);
    procedure DBConnectionAfterDisconnect(Sender: TObject);
    procedure DBConnectionBeforeConnect(Sender: TObject);
    procedure DBConnectionBeforeDisconnect(Sender: TObject);

    procedure DBConnectionLog(Sender: TSQLConnection; EventType: TDBEventType; 
      const Msg: String);
    procedure SQLMemoEnter(Sender: TObject);
    
  private
    { private declarations }

  public
    procedure PerformTransaction( IsCommit: Boolean );
    procedure SetBarText( Info: String = ''; SetState: Boolean = False ); inline;
    procedure WriteToLog( Report: String; Separate: Boolean = False );
    procedure ReportError( Err: Exception ); inline;
  end;

var
  MainForm: TMainForm;

implementation

uses dbconst; //see below, why and for what

{$R *.lfm}

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
var
  FindDB : TSearchRec;
begin
  Caption := Application.Title;
  DBConnection.LogEvents := LogAllEvents - [detFetch]; //because Lazarus don's save this. it's bug.

  LoginEdit.Text := STD_LOGIN;
  PasswordEdit.Text := STD_PASSWORD;

  LogMemo.Lines.Text := 'Welcome to IceFish!'     + EOLN +
                        'Standard login is '''    + STD_LOGIN    + '''.' + EOLN +
                        'Standard password is ''' + STD_PASSWORD + '''.' + EOLN
                                                                         + EOLN;

  //let's try to find default database
  if ( FindFirst( '*.fdb', faAnyFile, FindDB ) = 0 ) then
    DBNameEdit.Text := FindDB.Name;
  FindClose( FindDB );
end;

{ ============================================================================ }

procedure TMainForm.BrowseBtnClick(Sender: TObject);
begin
  if OpenDialog.Execute() then DBNameEdit.Text := OpenDialog.FileName;
end;

{ ============================================================================ }

procedure TMainForm.ConnectBtnClick(Sender: TObject);
begin
  try

    if DBConnection.Connected then begin
      if not ( MessageDlg('Are you sure do you want to interrupt connection and discard commit?',
                          mtWarning,
                          mbYesNo, 0) = mrYes ) then Exit;
      DBConnection.Connected := False;
    end;

    //trying to connect to database
    DBConnection.DatabaseName := DBNameEdit.Text;
    DBConnection.UserName := LoginEdit.Text;
    DBConnection.Password := PasswordEdit.Text;
    DBConnection.Connected := True; //perform attempt

    //reset status if everything is OK
    SetBarText();

  except
    on E: Exception do ReportError( E );
  end;
end;

procedure TMainForm.ExecuteBtnClick(Sender: TObject);
begin
  try
    SetBarText( 'Performing SQL query...' );
    SQLQuery.Active := False;
    SQLQuery.SQL.Text := SQLMemo.Text;

    if DMLTgBtn.Checked then begin { TODO 2 : idiotism intensifies }
      SQLQuery.ExecSQL();
      PageControl.ActivePage := LogTab;
    end else begin
      SQLQuery.Active := True;
      PageControl.ActivePage := DataTab;
    end;

    SetBarText();
  except
    on E: Exception do ReportError( E );
  end;
end;

{ ============================================================================ }

procedure TMainForm.CommitBtnClick(Sender: TObject);
    begin PerformTransaction( True );
      end;

procedure TMainForm.RollbackBtnClick(Sender: TObject);
    begin PerformTransaction( False );
      end;

{ EVENTS PROCESSING WITH LOGGING AND INFORMING =============================== }

procedure TMainForm.DBConnectionAfterConnect(Sender: TObject);
begin
  try
    //trying to start SQL transaction
    WriteToLog( 'Starting database transaction...' );
    SQLTransaction.Active := True;

    SetBarText( 'Connected', True );
    WriteToLog( 'Successfully connected.' + EOLN );

  except
    on E: Exception do ReportError( E );
  end;
end;

procedure TMainForm.DBConnectionAfterDisconnect(Sender: TObject);
    begin SetBarText( '', True );
          WriteToLog( 'Disconnected from database.' + EOLN );
      end;

procedure TMainForm.DBConnectionBeforeConnect(Sender: TObject);
    begin SetBarText( 'Establishing connection to database...' );
          WriteToLog( 'Performing connection attempt to database...' );
      end;

procedure TMainForm.DBConnectionBeforeDisconnect(Sender: TObject);
begin
  SQLTransaction.Active := False;
end;

{ ============================================================================ }

procedure TMainForm.DBConnectionLog(Sender: TSQLConnection; 
  EventType: TDBEventType; const Msg: String);
begin
  WriteToLog( Msg, True );
end;

procedure TMainForm.SQLMemoEnter(Sender: TObject);
begin
  //it executes only once for cleaning out "enter SQL here" message
  if SQLMemo.ReadOnly then begin
    SQLMemo.Lines.Text := '';
    SQLMemo.ReadOnly := False;
  end;
end;

{ COMMON ROUTINES ============================================================ }

procedure TMainForm.PerformTransaction( IsCommit: Boolean );
var
  OpStr : String; //yes, i'm an idiot
begin
  try
    SetBarText( 'Performing database transaction...' );
    PageControl.ActivePage := LogTab;

    if IsCommit then begin
      OpStr := 'commit';
      SQLTransaction.Action := caCommitRetaining;
    end else begin
      OpStr := 'rollback';
      SQLTransaction.Action := caRollbackRetaining;
    end;

    WriteToLog( 'Performing database ' + OpStr + '...' );

    //codeline below looks slightly weird, so let me to explain
    //TSQLTransaction DOES NOT perform ANY exception handling on transactions
    //that performing in cases when transaction still inactive, etc.
    //Idk why developers of SQLdb don't write that.
    //It also seems that I'm complete idiot, but I would to believe the opposite

    If not SQLTransaction.Active Then
      DatabaseError( STransNotActive, SQLTransaction ); //this

    SQLTransaction.EndTransaction(); //does transaction, but doesn't close it!
    SQLTransaction.Action := TCommitRollBackAction(caNone); //typecast wtf

    WriteToLog( 'Database ' + OpStr + ' successfully performed.' + EOLN );
    SetBarText();
  except
    on E: Exception do ReportError( E );
  end;
end;

procedure TMainForm.SetBarText( Info: String = ''; SetState: Boolean = False ); inline;
const
  BAR_STATE = 0;
  BAR_PROCESS = 1;
var
  SetBar: Integer;
begin
  if SetState then SetBar := BAR_STATE else SetBar := BAR_PROCESS;
  StatusBar.Panels.Items[SetBar].Text := Info;
  StatusBar.Update();
end; //wow much code

procedure TMainForm.WriteToLog( Report: String; Separate: Boolean = False );
begin
  if Separate then begin
    if not ( LogMemo.Lines[ LogMemo.Lines.Count-1 ] = '' ) then
      Report := EOLN + Report;
    Report += EOLN;
  end;
  LogMemo.Lines.Add( Report );
end;

procedure TMainForm.ReportError( Err: Exception ); inline;
begin
  { TODO 3 : Write more complex exception handling }
  SetBarText( 'Error occurred!' );
  PageControl.ActivePage := LogTab;
  WriteToLog( 'An error occurred:' + EOLN + Err.Message, True );
end;

end.

