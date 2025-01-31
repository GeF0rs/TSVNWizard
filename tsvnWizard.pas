(*
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Lesser General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *)

unit tsvnWizard;

{$R 'icons.res'}
{$R 'Strings.res'}

interface

uses
  ToolsAPI, SysUtils, Windows, Dialogs, Menus, Registry, ShellApi,
  Classes, Controls, Graphics, ImgList, ExtCtrls, ActnList, XMLIntf;

const
  VERSION = '1.8.1';

const
  SVN_PROJECT_EXPLORER      =  0;
  SVN_LOG_PROJECT           =  1;
  SVN_LOG_FILE              =  2;
  SVN_CHECK_MODIFICATIONS   =  3;
  SVN_ADD                   =  4;
  SVN_UPDATE                =  5;
  SVN_UPDATE_REV            =  6;
  SVN_COMMIT                =  7;
  SVN_DIFF                  =  8;
  SVN_REVERT                =  9;
  SVN_REPOSITORY_BROWSER    = 10;
  SVN_EDIT_CONFLICT         = 11;
  SVN_CONFLICT_OK           = 12;
  SVN_CREATE_PATCH          = 13;
  SVN_USE_PATCH             = 14;
  SVN_CLEAN                 = 15;
  SVN_IMPORT                = 16;
  SVN_CHECKOUT              = 17;
  SVN_BLAME                 = 18;
  SVN_SETTINGS              = 19;
  SVN_ABOUT                 = 20;
  SVN_SEPERATOR_1           = 21;
  SVN_ABOUT_PLUGIN          = 22;
  SVN_PLUGIN_PROJ_SETTINGS  = 23;
  SVN_VERB_COUNT            = 24;

// Define this to look for the "Version control" entry in the popup menu and hook into the submenu
{.$DEFINE UseVersionMenu}

var
  TSVNPath: string;
  SVNExe: string;
  TMergePath: string;
  Bitmaps: array[0..SVN_VERB_COUNT-1] of TBitmap;
  Actions: array[0..SVN_VERB_COUNT-1] of TAction;
  {$ifdef DEBUG}
  DebugFile: TextFile;
  {$endif}

type
  TProjectMenuTimer = class;

  TTortoiseSVN = class(TNotifierObject, IOTANotifier, IOTAWizard
                       {$if CompilerVersion > 18}, INTAProjectMenuCreatorNotifier{$endif} )
  strict private
    IsPopup: Boolean;
    IsProject: Boolean;
    IsEditor: Boolean;
    CmdFiles: string;
    Timer: TTimer;
    TSvnMenu: TMenuItem;
    IsDirectory: Boolean;

    function GetVerb(Index: Integer): string;
    function GetVerbState(Index: Integer): Word;
    
    procedure Tick( sender: TObject );
    procedure DiffClick( sender: TObject );
    procedure LogClick(Sender : TObject);
    procedure ConflictClick(Sender: TObject);
    procedure ConflictOkClick(Sender: TObject);
    procedure ExecuteVerb(Index: Integer);

    procedure UpdateAction( sender: TObject );
    procedure ExecuteAction( sender: TObject );

    function GetCurrentModule(): IOTAModule;
    function GetCurrentSourceEditor(): IOTASourceEditor;
    procedure GetCurrentModuleFileList( fileList: TStrings );

    function FindMenu(Item: TComponent): TMenu;
  private
    ProjectMenuTimer: TProjectMenuTimer;
    
    procedure TSVNMenuClick( Sender: TObject );
    procedure CreateMenu; overload;
    procedure CreateMenu(Parent: TMenuItem; const Ident: string = ''); overload;

    ///  <summary>
    ///  Returns the path for the TortoiseSVN command depending on the files in
    ///  a project. This includes entries such as ..\..\MyUnit.pas.
    ///  </summary>
    function GetPathForProject(Project: IOTAProject): string;

    procedure GetFiles(Files: TStringList);

    function CheckModified(Project: IOTAProject): Integer;

    class procedure TSVNExec( Params: string );
    class procedure TSVNMergeExec( Params: string );
  public
    constructor Create;
    destructor Destroy; override;

    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;

    { INTAProjectMenuCreatorNotifier }

    { The result will be inserted into the project manager local menu. Menu
      may have child menus. }
    function AddMenu(const Ident: string): TMenuItem;

    { Return True if you wish to install a project manager menu item for this
      ident.  In cases where the project manager node is a file Ident will be
      a fully qualified file name. }
    function CanHandle(const Ident: string): Boolean;
  end;

  TIdeNotifier = class(TNotifierObject, IOTAIDENotifier)
  protected
    { This procedure is called for many various file operations within the
      IDE }
    procedure FileNotification(NotifyCode: TOTAFileNotification;
      const FileName: string; var Cancel: Boolean);

    { This function is called immediately before the compiler is invoked.
      Set Cancel to True to cancel the compile }
    procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;

    { This procedure is called immediately following a compile.  Succeeded
      will be true if the compile was successful }
    procedure AfterCompile(Succeeded: Boolean); overload;

    { The associated item is being destroyed so all references should be dropped.
      Exceptions are ignored. }
    procedure Destroyed;

    class function RegisterPopup(Module: IOTAModule): Boolean; overload;

    class function RegisterPopup(View: IOTAEditView): Boolean; overload;

    class procedure RegisterEditorNotifier(Module: IOTAModule);
    class procedure RemoveEditorNotifier(Module: IOTAModule);
  end;

  TModuleArray = array of IOTAModule;

  TModuleNotifier = class(TModuleNotifierObject, IOTAModuleNotifier)
  strict private
    _FileName: string;
    _Notifier: Integer;
    _Module: IOTAModule;
  protected
    { This procedure is called immediately after the item is successfully saved.
      This is not called for IOTAWizards }
    procedure AfterSave;

    { The associated item is being destroyed so all references should be dropped.
      Exceptions are ignored. }
    procedure Destroyed;
  public
    constructor Create(Filename: string; Module: IOTAModule);
    destructor Destroy; override;

    procedure RemoveBindings;

    property FileName: string read _FileName write _FileName;
  end;

  TProjectNotifier = class(TModuleNotifierObject, IOTAProjectNotifier)
  strict private
    FModuleCount: Integer;
    FModules: TModuleArray;
    FProject: IOTAProject;
    FFileName: String;

    procedure SetModuleCount(const Value: Integer);
  private
    function GetModule(Index: Integer): IOTAModule;
    procedure SetModule(Index: Integer; const Value: IOTAModule);
  protected
    { IOTAModuleNotifier }

    { User has renamed the module }
    procedure ModuleRenamed(const NewName: string); overload;

    { IOTAProjectNotifier }

    { This notifier will be called when a file/module is added to the project }
    procedure ModuleAdded(const AFileName: string);

    { This notifier will be called when a file/module is removed from the project }
    procedure ModuleRemoved(const AFileName: string);

    { This notifier will be called when a file/module is renamed in the project }
    procedure ModuleRenamed(const AOldFileName, ANewFileName: string); overload;

    { The associated item is being destroyed so all references should be dropped.
      Exceptions are ignored. }
    procedure Destroyed;

    constructor Create(const FileName: string);   

    property ModuleCount: Integer read FModuleCount write SetModuleCount;

    property Modules: TModuleArray read FModules write FModules;

    property Module[Index: Integer]: IOTAModule read GetModule write SetModule;

    property Project: IOTAProject read FProject write FProject;
  end;

  TProjectMenuTimer = class(TTimer)
  private
    procedure TimerTick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TEditorNotifier = class(TNotifierObject, IOTAEditorNotifier, IOTANotifier)
  strict private
    _Editor: IOTAEditor;
    _Notifier: Integer;
    _Opened: Boolean;
  public
    constructor Create(const Editor: IOTAEditor);                  
    destructor Destroy; override;

    { This associated item was modified in some way. This is not called for
      IOTAWizards }
    procedure Modified;

    { This procedure is called immediately after the item is successfully saved.
      This is not called for IOTAWizards }
    procedure AfterSave;

    { Called when a new edit view is created(opInsert) or destroyed(opRemove) }
    procedure ViewNotification(const View: IOTAEditView; Operation: TOperation);

    { Called when a view is activated }
    procedure ViewActivated(const View: IOTAEditView);

    procedure RemoveBindings;

    { The associated item is being destroyed so all references should be dropped.
      Exceptions are ignored. }
    procedure Destroyed;

    property Opened: Boolean read _Opened write _Opened;
  end;

  IEditorMenuPopupListener = interface
  ['{F2123551-23F0-40BB-9B44-8F0085FE19E1}']
    procedure RegisterPopup(const APopup: TPopupMenu);
  end;

  TEditorMenuPopupListener = class(TInterfacedObject, IEditorMenuPopupListener)
  private
    FPopup: TPopupMenu;
    FOldPopupListener: TNotifyEvent;

    procedure Remove;
  public
    destructor Destroy; override;

    procedure MenuPopup(Sender: TObject);
    procedure RegisterPopup(const APopup: TPopupMenu);
  end;

{$IFNDEF DLL_MODE}

procedure Register;

{$ELSE}

function InitWizard(const BorlandIDEServices: IBorlandIDEServices;
  RegisterProc: TWizardRegisterProc;
  var Terminate: TWizardTerminateProc): Boolean; stdcall;

{$ENDIF}

implementation

uses TypInfo, Contnrs, UHelperFunctions, IniFiles, UFmProjectSettings, Forms;

var
  MenuCreatorNotifier: Integer = -1;
  IDENotifierIndex   : Integer = -1;
  AboutBoxIndex      : Integer = -1;
  NotifierList : TStringList;
  TortoiseSVN: TTortoiseSVN;
  EditPopup: TPopupMenu;
  EditMenuItem: TMenuItem;
  ImgIdx: array[0..SVN_VERB_COUNT] of Integer;
  EditorNotifierList: TStringList;
  ModifiedFiles: TStringList;
  ModuleNotifierList: TStringList;
  EditorMenuPopupListener: IEditorMenuPopupListener;
{$IFDEF UseVersionMenu}
  VersionControlMenuPopup: TMenuItem;
{$ENDIF}

procedure WriteDebug(Text: string);
const
  LogFile = 'c:\TSVNDebug.log';
begin
{$ifdef DEBUG}
  try
    AssignFile(DebugFile, 'c:\TSVNDebug.log');
    if (FileExists(LogFile)) then
      Append(DebugFile)
    else
      ReWrite(DebugFile);
  except
  end;

  try
    WriteLn(DebugFile, Text);
  except
  end;

  try
    CloseFile(DebugFile);
  except
  end;
{$endif}
end;

function GetBitmapName(Index: Integer): string;
begin
  case Index of
    SVN_PROJECT_EXPLORER:
      Result:= 'explorer';
    SVN_LOG_PROJECT,
    SVN_LOG_FILE:
      Result:= 'log';
    SVN_CHECK_MODIFICATIONS:
      Result:= 'check';
    SVN_ADD:
      Result:= 'add';
    SVN_UPDATE,
    SVN_UPDATE_REV:
      Result:= 'update';
    SVN_COMMIT:
      Result:= 'commit';
    SVN_DIFF:
      Result:= 'diff';
    SVN_REVERT:
      Result:= 'revert';
    SVN_REPOSITORY_BROWSER:
      Result:= 'repository';
    SVN_SETTINGS:
      Result:= 'settings';
    SVN_PLUGIN_PROJ_SETTINGS:
      Result := 'projsettings';
    SVN_ABOUT,
    SVN_ABOUT_PLUGIN:
      Result:= 'about';
    SVN_EDIT_CONFLICT:
      Result := 'edconflict';
    SVN_CONFLICT_OK:
      Result := 'conflictok';
    SVN_CREATE_PATCH:
      Result := 'crpatch';
    SVN_USE_PATCH:
      Result := 'usepatch';
    SVN_CLEAN:
      Result := 'clean';
    SVN_IMPORT:
      Result := 'import';
    SVN_CHECKOUT:
      Result := 'checkout';
    SVN_BLAME:
      Result := 'blame';
  end;
end;

function TTortoiseSVN.GetCurrentModule: IOTAModule;
begin
  Result := (BorlandIDEServices as IOTAModuleServices).CurrentModule;
end;

procedure TTortoiseSVN.GetCurrentModuleFileList( FileList: TStrings );
var
  ModServices: IOTAModuleServices;
  Module: IOTAModule;
  Project: IOTAProject;
  {$if CompilerVersion < 21} // pre Delphi2010
  ModInfo: IOTAModuleInfo;
  {$endif}
  FileName: string;
begin
  FileList.Clear;

  if (IsPopup) and (not IsEditor) then
  begin
    Project := (BorlandIDEServices as IOTAProjectManager).GetCurrentSelection(FileName);

    {$if CompilerVersion >= 21} // Delphi2010+
    Project.GetAssociatedFiles(FileName, FileList);
    {$else}
    ModInfo := Project.FindModuleInfo(FileName);
    if (ModInfo <> nil) then
    begin
      GetModuleFiles(FileList, ModInfo.OpenModule);
    end;
    {$endif}
  end else
  begin
    ModServices := BorlandIDEServices as IOTAModuleServices;
    if (ModServices <> nil) then
    begin
      Module := ModServices.CurrentModule;
      GetModuleFiles(FileList, Module);
    end;
  end;
end;

function TTortoiseSVN.GetCurrentSourceEditor: IOTASourceEditor;
var
  CurrentModule: IOTAModule;
  Editor: IOTAEditor; 
  I: Integer;
begin
  Result := nil;
  CurrentModule := GetCurrentModule;
  if (Assigned(CurrentModule)) then
  begin
    for I := 0 to CurrentModule.ModuleFileCount - 1 do
    begin
      Editor := CurrentModule.ModuleFileEditors[I];
      
      if Supports(Editor, IOTASourceEditor, Result) then
        Exit;
    end;
  end;
end;

procedure TTortoiseSVN.GetFiles(Files: TStringList);
var
  Ident: string;
  Project: IOTAProject;
  ItemList: TStringList;
  {$if CompilerVersion < 21} // pre Delphi2010
  ModInfo: IOTAModuleInfo;
  {$endif}
begin
  if (IsPopup) and (not IsEditor) then
  begin
    {
      The call is from the Popup and a file is selected
    }
    Ident := '';
    Project := (BorlandIDEServices as IOTAProjectManager).GetCurrentSelection(Ident);

    ItemList := TStringList.Create;
    try
      {$if CompilerVersion >= 21} // Delphi2010+
      Project.GetAssociatedFiles(Ident, ItemList);
      {$else}
      ModInfo := Project.FindModuleInfo(Ident);
      if (ModInfo <> nil) then
      begin
        GetModuleFiles(ItemList, ModInfo.OpenModule);
      end;
      {$endif}

      if (ItemList.Count > 0) then
      begin
        Files.AddStrings(ItemList);
      end else
      begin
        if (DirectoryExists(Ident)) then
          Files.Add(Ident);
      end;
    finally
      ItemList.Free;
    end;
  end else
  begin
    GetCurrentModuleFileList(Files);
  end;
end;

procedure GetModifiedItems( ItemList: TStrings );
begin
  WriteDebug('TGetModifiedItems() :: start');
  ItemList.Clear;

  if Assigned(ModifiedFiles) and (ModifiedFiles.Count > 0) then
  begin
    ItemList.AddStrings(ModifiedFiles);
  end;
  WriteDebug('TGetModifiedItems() :: done');
end;

function TTortoiseSVN.AddMenu(const Ident: string): TMenuItem;
begin
  {
    Get's created every time a user right-clicks a file or project.
  }
  Result := TMenuItem.Create(nil);
  Result.Name := 'Submenu';
  Result.Caption := 'TortoiseSVN';
  Result.OnClick := TSVNMenuClick;

  if (SameText(Ident, sFileContainer)) then
  begin
    CreateMenu(Result, sFileContainer);
    Result.Tag := 1;
  end
  else if (SameText(Ident, sProjectContainer)) then
  begin
    CreateMenu(Result, sProjectContainer);
    Result.Tag := 2;
  end
  else if (SameText(Ident, sDirectoryContainer)) then
  begin
    CreateMenu(Result, sDirectoryContainer);
    Result.Tag := 8;
  end;

  // Disable for now - didn't work properly
  // ProjectMenuTimer := TProjectMenuTimer.Create(Result);
end;

function TTortoiseSVN.CanHandle(const Ident: string): Boolean;
begin
  Result := SameText(Ident, sFileContainer) or
            SameText(Ident, sProjectContainer) or
            SameText(Ident, sDirectoryContainer);
end;

function TTortoiseSVN.CheckModified(Project: IOTAProject): Integer;
var
  ItemList: TStringList;
  ModifiedItems: Boolean;
  ModifiedItemsMessage: string;
  I: Integer;
begin
  try
    WriteDebug(Format('TTortoiseSVN.CheckModified(%s) :: start', [Project.FileName]));
  except
  end;
  Result := mrNo;

  ItemList := TStringList.Create;
  try
    GetModifiedItems(ItemList);
    ModifiedItems := (ItemList.Count > 0);

    if ModifiedItems then
    begin
      ModifiedItemsMessage := GetString(25) + #13#10#13#10;
      for I := 0 to ItemList.Count-1 do
        ModifiedItemsMessage := ModifiedItemsMessage + '    ' + ItemList[I] + #13#10;
      ModifiedItemsMessage := ModifiedItemsMessage + #13#10 + GetString(26);
    end;
  finally
    ItemList.Free;
  end;

  if ModifiedItems then
  begin
    Result := MessageDlg( ModifiedItemsMessage, mtWarning, [mbYes, mbNo, mbCancel], 0 );
  end;

  try
    WriteDebug(Format('TTortoiseSVN.CheckModified(%s) :: done', [Project.FileName]));
  except
  end;
end;

procedure TTortoiseSVN.ConflictClick(Sender: TObject);
var
  Files: TStringList;
  Item: TComponent;
begin
  if (Sender is TComponent) then
  begin
    Item := TComponent(Sender);

    Files := TStringList.Create;
    try
      GetFiles(Files);

      if (Files.Count > 1) then
        TSVNExec( '/command:conflicteditor /notempfile /path:' + AnsiQuotedStr( Files[Item.Tag], '"' ) )
      else if (Files.Count = 1) then
        TSVNExec( '/command:conflicteditor /notempfile /path:' + AnsiQuotedStr( Files[0], '"' ) );
    finally
      Files.Free;
    end;
  end;
end;

procedure TTortoiseSVN.ConflictOkClick(Sender: TObject);
var
  Files: TStringList;
  Item: TComponent;
begin
  if (Sender is TComponent) then
  begin
    Item := TComponent(Sender);

    Files := TStringList.Create;
    try
      GetFiles(Files);

      if (Files.Count > 1) then
        TSVNExec( '/command:resolve /notempfile /path:' + AnsiQuotedStr( Files[Item.Tag], '"' ) )
      else if (Files.Count = 1) then
        TSVNExec( '/command:resolve /notempfile /path:' + AnsiQuotedStr( Files[0], '"' ) );
    finally
      Files.Free;
    end;
  end;
end;

constructor TTortoiseSVN.Create;
var
  Reg: TRegistry;
  I: Integer;

// defines for 64-bit registry access, copied from Windows include file
// (older IDE versions won't find them otherwise)
const
  KEY_WOW64_64KEY = $0100;
  KEY_WOW64_32KEY = $0200;

  procedure SetValues(const AReg: TRegistry);
  var
    Directory: string;
  begin
    TSVNPath   := Reg.ReadString( 'ProcPath' );
    TMergePath := Reg.ReadString( 'TMergePath' );

    // Check if the user has the svn.exe command line tool installed
    Directory  := Reg.ReadString( 'Directory' );
    SVNExe := IncludeTrailingPathDelimiter(Directory) + 'bin' + PathDelim + 'svn.exe';
    if (not FileExists(SVNExe)) then
      SVNExe := '';
  end;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly( '\SOFTWARE\TortoiseSVN' ) then
    begin
      SetValues(Reg);
    end
    else
    begin
      // try 64 bit registry
      Reg.Access := Reg.Access or KEY_WOW64_64KEY;
      if Reg.OpenKeyReadOnly( '\SOFTWARE\TortoiseSVN' ) then
      begin
        SetValues(Reg);
      end
      else
      begin
        // try WOW64 bit registry
        Reg.Access := Reg.Access or KEY_WOW64_32KEY;
        if Reg.OpenKeyReadOnly( '\SOFTWARE\TortoiseSVN' ) then
        begin
          SetValues(Reg);
        end;
      end;
    end;
  finally
    Reg.CloseKey;
    Reg.Free;
  end;

  TSvnMenu:= nil;

  Timer := TTimer.Create(nil);
  Timer.Interval := 200;
  Timer.OnTimer := Tick;
  Timer.Enabled := True;

  TortoiseSVN := Self;

  for I := 0 to SVN_VERB_COUNT do
  begin
    ImgIdx[I] := -1;
  end;
end;

procedure TTortoiseSVN.CreateMenu(Parent: TMenuItem; const Ident: string = '');
var
  Item: TMenuItem;
  I: Integer;
  Menu: TMenu;
  MenuType: Integer;
begin
  if (Parent = nil) then Exit;

  Menu := FindMenu(Parent);

  // Little speed-up (just running "SameText" once instead of every iteration
  if (SameText(Ident, sFileContainer)) then
    MenuType := 1
  else if (SameText(Ident, sDirectoryContainer)) then
    MenuType := 2
  else if (SameText(Ident, sProjectContainer)) then
    MenuType := 3
  else if (Ident <> '') then
    MenuType := 4
  else
    MenuType := 0;

  for I := 0 to SVN_VERB_COUNT - 1 do
  begin
    if (MenuType <> 0) then
    begin
      // Ignore the project specific entries for the file container
      if (MenuType = 1) and
         (I in [SVN_PROJECT_EXPLORER, SVN_LOG_PROJECT, SVN_REPOSITORY_BROWSER, SVN_IMPORT, SVN_CHECKOUT, SVN_CLEAN, SVN_USE_PATCH, SVN_PLUGIN_PROJ_SETTINGS]) then
        Continue;

      // Ignore the project and some file specific entries for the directory container
      if (MenuType = 2) and
         (I in [SVN_PROJECT_EXPLORER, SVN_LOG_PROJECT, SVN_REPOSITORY_BROWSER, SVN_IMPORT, SVN_CHECKOUT, SVN_CLEAN, SVN_USE_PATCH, SVN_CONFLICT_OK, SVN_EDIT_CONFLICT, SVN_PLUGIN_PROJ_SETTINGS]) then
        Continue;

      // Ignore the file specific entries for the project container
      if (MenuType = 3) and
         (I in [SVN_LOG_FILE, SVN_DIFF, SVN_CONFLICT_OK, SVN_EDIT_CONFLICT]) then
        Continue;

      // Ignore about and settings in the popup
      if (I in [SVN_ABOUT, SVN_SETTINGS, SVN_ABOUT_PLUGIN]) then
        Continue;
    end;

    if (Bitmaps[I] = nil) then
    begin
      Bitmaps[I] := TBitmap.Create;
      try
        Bitmaps[I].LoadFromResourceName( HInstance, getBitmapName(i) );
      except
      end;
    end;

    if (Actions[I] = nil) then
    begin
      Actions[I] := TAction.Create(nil);
      Actions[I].ActionList := (BorlandIDEServices as INTAServices).ActionList;
      Actions[I].Caption := GetVerb(I);
      Actions[I].Hint := GetVerb(I);

      if (Bitmaps[I].Width = 16) and (Bitmaps[I].height = 16) then
      begin
        Actions[I].ImageIndex := (BorlandIDEServices as INTAServices).AddMasked(Bitmaps[I], clBlack);
      end;

      Actions[I].OnUpdate:= UpdateAction;
      Actions[I].OnExecute:= ExecuteAction;
      Actions[I].Tag := I;
    end;

    Item := TMenuItem.Create(Parent);
    if (I <> SVN_DIFF) and
       (I <> SVN_LOG_FILE) and
       (I <> SVN_EDIT_CONFLICT) and
       (I <> SVN_CONFLICT_OK) then
    begin
      Item.Action := Actions[I];
    end
    else
    begin
      if (Item.ImageIndex = -1) then
      begin
        if (Menu <> nil) then
          Item.ImageIndex := Menu.Images.AddMasked(Bitmaps[I], clBlack)
      end;
    end;
    Item.Tag := I;

    Parent.Add(Item);
  end;
end;

procedure TTortoiseSVN.Tick(Sender: TObject);
var
  Intf: INTAServices;
  I, X, Index: Integer;
  Project: IOTAProject;
  Notifier: TProjectNotifier;
begin
  if (BorlandIDEServices.QueryInterface(INTAServices, Intf) = S_OK) then
  begin
    Self.CreateMenu;
    Timer.Free;
    Timer := nil;
  end;

  for I := 0 to (BorlandIDEServices as IOTAModuleServices).ModuleCount - 1 do
  begin
    TIdeNotifier.RegisterPopup((BorlandIDEServices as IOTAModuleServices).Modules[I]);
    TIdeNotifier.RegisterEditorNotifier((BorlandIDEServices as IOTAModuleServices).Modules[I]);

    if (Supports((BorlandIDEServices as IOTAModuleServices).Modules[I], IOTAProject, Project)) then
    begin
      Notifier := TProjectNotifier.Create(Project.FileName);
      Notifier.Project := Project;
      Notifier.ModuleCount := Project.GetModuleFileCount;
      for X := 0 to Notifier.ModuleCount - 1 do
      begin
        Notifier.Module[X] := Project.ModuleFileEditors[X].Module;
      end;

      Index := Project.AddNotifier(Notifier as IOTAProjectNotifier);
      if (Index >= 0) then
        NotifierList.AddObject(Project.FileName, Pointer(Index));
    end;
  end;
end;

procedure TTortoiseSVN.TSVNMenuClick( Sender: TObject );
var
  ItemList, Files: TStringList;
  I: integer;
  Diff, Log, Item, Conflict, ConflictOk: TMenuItem;
  Ident: string;
  Parent: TMenuItem;
  Project: IOTAProject;
  {$if CompilerVersion < 21} // pre Delphi2010
  ModInfo: IOTAModuleInfo;
  {$endif}
begin
  // update the diff item and submenu; the diff action is handled by the
  // menu item itself, not by the action list
  // the 'log file' item behaves in a similar way

  if (Sender is TMenuItem) then
    Parent := TMenuItem(Sender)
  else
    Exit;

  IsPopup := (Parent.Tag > 0);

  IsProject := (Parent.Tag and 2) = 2;

  IsEditor := (Parent.Tag and 4) = 4;

  IsDirectory := (Parent.Tag and 4) = 4;

  Diff := nil; Log := nil; Conflict := nil; ConflictOk := nil;

  for I := 0 to Parent.Count - 1 do
  begin
    if (Parent.Items[I].Tag = SVN_DIFF) then
    begin
      Diff := Parent.Items[I];
      Diff.Action:= nil;
      Diff.OnClick:= nil;
      Diff.Enabled:= False;
      Diff.Caption:= GetString(SVN_DIFF);
      if (not IsPopup) then
        Diff.ImageIndex := Actions[SVN_DIFF].ImageIndex;
      Diff.Clear;
    end
    else if (Parent.Items[I].Tag = SVN_LOG_FILE) then
    begin
      Log := Parent.Items[I];
      Log.Action := nil;
      Log.OnClick := nil;
      Log.Enabled := False;
      Log.Caption:= GetString(SVN_LOG_FILE);
      if (not IsPopup) then
        Log.ImageIndex := Actions[SVN_LOG_FILE].ImageIndex;
      Log.Clear();
    end
    else if (Parent.Items[I].Tag = SVN_EDIT_CONFLICT) then
    begin
      Conflict := Parent.Items[I];
      Conflict.Action := nil;
      Conflict.OnClick := nil;
      Conflict.Enabled := False;
      Conflict.Caption:= GetString(SVN_EDIT_CONFLICT);
      if (not IsPopup) then
        Conflict.ImageIndex := Actions[SVN_EDIT_CONFLICT].ImageIndex;
      Conflict.Clear();
    end
    else if (Parent.Items[I].Tag = SVN_CONFLICT_OK) then
    begin
      ConflictOk := Parent.Items[I];
      ConflictOk.Action := nil;
      ConflictOk.OnClick := nil;
      ConflictOk.Enabled := False;
      ConflictOk.Caption:= GetString(SVN_CONFLICT_OK);
      if (not IsPopup) then
        ConflictOk.ImageIndex := Actions[SVN_CONFLICT_OK].ImageIndex;
      ConflictOk.Clear();
    end;
  end;

  Files := TStringList.create;

  if (IsPopup) and (not IsEditor) then
  begin
    {
      The call is from the Popup and a file is selected
    }
    Ident := '';
    Project := (BorlandIDEServices as IOTAProjectManager).GetCurrentSelection(Ident);

    ItemList := TStringList.Create;
    try
      {$if CompilerVersion >= 21} // Delphi2010+
      Project.GetAssociatedFiles(Ident, ItemList);
      {$else}
      ModInfo := Project.FindModuleInfo(Ident);
      if (ModInfo <> nil) then
      begin
        GetModuleFiles(ItemList, ModInfo.OpenModule);
      end;
      {$endif}

      if (ItemList.Count > 0) then
      begin
        Files.AddStrings(ItemList);
      end else
      begin
        if (DirectoryExists(Ident)) then
          Files.Add(Ident);
      end;
    finally
      ItemList.Free;
    end;
  end else
  begin
    GetCurrentModuleFileList(Files);
  end;

  CmdFiles := '';
  for I := 0 to Files.Count - 1 do
  begin
    CmdFiles := CmdFiles + Files[I];
    if (I < Files.Count - 1) then
      CmdFiles := CmdFiles + '*';
  end;

  if (Files.Count > 0) then
  begin
    if (Diff <> nil) then
      Diff.Enabled:= True;

    if (Log <> nil) then
      Log.Enabled := True;

    if (Conflict <> nil) then
      Conflict.Enabled := True;

    if (ConflictOk <> nil) then
      ConflictOk.Enabled := True;

    if Files.Count > 1 then
    begin
      for I := 0 to Files.Count - 1 do begin
        if (Diff <> nil) then
        begin
          Item := TMenuItem.Create(diff);
          Item.Caption:= ExtractFileName( files[i] );
          Item.OnClick:= DiffClick;
          Item.Tag:= I;
          Diff.Add(Item);
        end;

        if (Log <> nil) then
        begin
          Item := TMenuItem.Create(log);
          Item.Caption := ExtractFileName( files[i] );
          Item.OnClick := LogClick;
          Item.Tag := I;
          Log.Add(Item);
        end;

        if (Conflict <> nil) then
        begin
          Item := TMenuItem.Create(log);
          Item.Caption := ExtractFileName( files[i] );
          Item.OnClick := ConflictClick;
          Item.Tag := I;
          Conflict.Add(Item);
        end;

        if (ConflictOk <> nil) then
        begin
          Item := TMenuItem.Create(log);
          Item.Caption := ExtractFileName( files[i] );
          Item.OnClick := ConflictOkClick;
          Item.Tag := I;
          ConflictOk.Add(Item);
        end;
      end;
    end else
    begin  // files.Count = 1
      if (Diff <> nil) then
      begin
        Diff.Caption:= GetString(SVN_DIFF) + ' ' + ExtractFileName( Files[0] );
        Diff.OnClick:= DiffClick;
      end;

      if (Log <> nil) then
      begin
        Log.Caption := GetString(SVN_LOG_FILE) + ' ' + ExtractFileName( Files[0] );
        Log.OnClick := LogClick;
      end;

      if (Conflict <> nil) then
      begin
        Conflict.Caption := GetString(SVN_EDIT_CONFLICT) + ' ' + ExtractFileName( Files[0] );
        Conflict.OnClick := ConflictClick;
      end;

      if (ConflictOk <> nil) then
      begin
        ConflictOk.Caption := GetString(SVN_CONFLICT_OK) + ' ' + ExtractFileName( Files[0] );
        ConflictOk.OnClick := ConflictOkClick;
      end;
    end;
  end;
  Files.free;
end;

class procedure TTortoiseSVN.TSVNMergeExec(params: string);
var
  CmdLine: AnsiString;
begin
  CmdLine := AnsiString(TMergePath + ' ' + params);
  WinExec( PAnsiChar(CmdLine), SW_SHOW );
end;

procedure TTortoiseSVN.DiffClick( Sender: TObject );
var
  Files: TStringList;
  Item: TComponent;
begin
  if (Sender is TComponent) then
  begin
    Item := TComponent(Sender);

    Files := TStringList.Create;
    try
      GetFiles(Files);

      if (Files.Count > 1) then
        TSVNExec( '/command:diff /notempfile /path:' + AnsiQuotedStr( Files[Item.Tag], '"' ) )
      else if (Files.Count = 1) then
        TSVNExec( '/command:diff /notempfile /path:' + AnsiQuotedStr( Files[0], '"' ) );
    finally
      Files.Free;
    end;
  end;
end;

procedure TTortoiseSVN.LogClick(Sender : TObject);
var
  Files : TStringList;
  Item  : TComponent;
begin
  if (Sender is TComponent) then
  begin
    Item  := TComponent(Sender);

    Files := TStringList.Create;
    try
      GetFiles(Files);

      if (Files.Count > 1) then
        TSVNExec('/command:log /notempfile /path:' + AnsiQuotedStr(Files[Item.Tag], '"'))
      else if (Files.Count = 1) then
        TSVNExec('/command:log /notempfile /path:' + AnsiQuotedStr(Files[0], '"'));
    finally
      Files.Free;
    end;
  end;
end;

procedure TTortoiseSVN.CreateMenu;
var
  MainMenu: TMainMenu;
  ProjManager: IOTAProjectManager;
  Services: IOTAServices;
begin
  if (TSvnMenu <> nil) then exit;

  TSvnMenu := TMenuItem.Create(nil);
  TSvnMenu.Caption := 'TortoiseSVN';
  TSvnMenu.Name := 'TortoiseSVNMain';
  TSvnMenu.OnClick := TSVNMenuClick;

  CreateMenu(TSvnMenu);

  MainMenu := (BorlandIDEServices as INTAServices).MainMenu;
  MainMenu.Items.Insert(MainMenu.Items.Count-1, TSvnMenu);

  {$if CompilerVersion > 18} // Delphi 2007+
  if Supports(BorlandIDEServices, IOTAProjectManager, ProjManager) then
  begin
    MenuCreatorNotifier := ProjManager.AddMenuCreatorNotifier(Self);
  end;
  {$endif}

  if Supports(BorlandIDEServices, IOTAServices, Services) then
  begin
    IDENotifierIndex := Services.AddNotifier(TIdeNotifier.Create);
  end;
end;

destructor TTortoiseSVN.Destroy;
var
  I: Integer;
begin
  if (TSvnMenu <> nil) then
  begin
    TSvnMenu.free;
  end;

  for I := Low(Actions) to High(Actions) do
  begin
    try
      if (Actions[I] <> nil) then
        Actions[I].Free;
    except
    end;
  end;

  for I := Low(Bitmaps) to High(Bitmaps) do
  begin
    try
      if (Bitmaps[I] <> nil) then
        Bitmaps[I].Free;
    except
    end;
  end;

  TortoiseSVN := nil;

  inherited;
end;

function TTortoiseSVN.GetVerb(Index: Integer): string;
begin
  Result := GetString(index);
  Exit;
end;

const vsEnabled = 1;

function TTortoiseSVN.GetVerbState(Index: Integer): Word;
begin
  Result:= 0;
  case index of
    SVN_PROJECT_EXPLORER,
    SVN_LOG_PROJECT,
    SVN_CHECK_MODIFICATIONS,
    SVN_ADD,
    SVN_UPDATE,
    SVN_UPDATE_REV,
    SVN_COMMIT,
    SVN_REVERT,
    SVN_BLAME,
    SVN_CREATE_PATCH,
    SVN_USE_PATCH,
    SVN_CLEAN,
    SVN_IMPORT:
    begin
      // Only enabled if a project is loaded
      if GetCurrentProject <> nil then
        Result:= vsEnabled;
    end;
    SVN_LOG_FILE,
    SVN_DIFF,
    SVN_EDIT_CONFLICT,
    SVN_CONFLICT_OK:
    begin
      // these verbs state is updated by the menu itself
    end;
    SVN_REPOSITORY_BROWSER,
    SVN_SETTINGS,
    SVN_PLUGIN_PROJ_SETTINGS,
    SVN_ABOUT,
    SVN_ABOUT_PLUGIN,
    SVN_CHECKOUT:
    begin
      // Always enabled
      Result := vsEnabled;
    end;
  end;
end;

class procedure TTortoiseSVN.TSVNExec( Params: string );
var
  CmdLine: AnsiString;
begin
  CmdLine := AnsiString(TSVNPath + ' ' + params);
  WinExec( PAnsiChar(cmdLine), SW_SHOW );
end;

procedure TTortoiseSVN.ExecuteVerb(Index: Integer);
var
  Project: IOTAProject;
  Response: Integer;
  FileName, Cmd: string;
  SourceEditor: IOTASourceEditor;
  Line: Integer;
  FmProjectSettings: TFmProjectSettings;
  EndRev: Integer;
  Major, Minor, Build: Integer;
  RevStr: string;
  About: string;
  Files: TStringList;
begin
  Project := GetCurrentProject();

  case index of
    SVN_PROJECT_EXPLORER:
      if (not IsPopup) or (IsProject) then
      begin
        {
          If it's a project which is accessed via the popup menu, then that
          project needs to be loaded and not the popup of the current file
          in the editor.
        }
        if (IsProject) then
        begin
          Project := (BorlandIDEServices as IOTAProjectManager).GetCurrentSelection(FileName);
        end;

        if (Project <> nil) then
          ShellExecute( 0, 'open', pchar( ExtractFilePath(Project.GetFileName) ), '', '', SW_SHOWNORMAL );
      end;
    SVN_LOG_PROJECT:
      if (not IsPopup) or (IsProject) then
      begin
        {
          If it's a project which is accessed via the popup menu, then that
          project needs to be loaded and not the popup of the current file
          in the editor.
        }
        if (IsProject) then
        begin
          Project := (BorlandIDEServices as IOTAProjectManager).GetCurrentSelection(FileName);
        end;

        if (Project <> nil) then
          TSVNExec( '/command:log /notempfile /path:' + AnsiQuotedStr( ExtractFilePath(Project.FileName), '"' ) );
      end;
    SVN_LOG_FILE:
        // this verb is handled by its menu item
        ;
    SVN_CHECK_MODIFICATIONS:
      if ((not IsPopup) or (IsProject)) and (not IsEditor) then
      begin
        {
          If it's a project which is accessed via the popup menu, then that
          project needs to be loaded and not the popup of the current file
          in the editor.
        }
        if (IsProject) then
        begin
          Project := (BorlandIDEServices as IOTAProjectManager).GetCurrentSelection(FileName);
        end;

        if (Project <> nil) then
          TSVNExec( '/command:repostatus /notempfile /path:' + AnsiQuotedStr( GetPathForProject(Project), '"' ) );
      end else
      begin
        {
          The call is from the Popup and a file is selected
        }
        Cmd := '/command:repostatus /notempfile /path:' + AnsiQuotedStr(CmdFiles, '"');

        TSVNExec(Cmd);
      end;
    SVN_ADD:
      if (not IsPopup) or (IsProject) then
      begin
        {
          If it's a project which is accessed via the popup menu, then that
          project needs to be loaded and not the popup of the current file
          in the editor.
        }
        if (IsProject) then
        begin
          Project := (BorlandIDEServices as IOTAProjectManager).GetCurrentSelection(FileName);
        end;

        if (Project <> nil) then
          TSVNExec( '/command:add /notempfile /path:' + AnsiQuotedStr( ExtractFilePath(Project.GetFileName), '"' ) );
      end else
      begin
        {
          The call is from the Popup and a file is selected
        }
        Cmd := '/command:add /notempfile /path:' + AnsiQuotedStr(CmdFiles, '"');

        TSVNExec(Cmd);
      end;
    SVN_UPDATE,
    SVN_UPDATE_REV:
      if (not IsPopup) or (IsProject) then
      begin
        {
          If it's a project which is accessed via the popup menu, then that
          project needs to be loaded and not the popup of the current file
          in the editor.
        }
        if (IsProject) then
        begin
          Project := (BorlandIDEServices as IOTAProjectManager).GetCurrentSelection(FileName);
        end;

        if (Project <> nil) then
        begin
          Response := CheckModified(Project);

          if (Response = mrYes) then
          begin
            (BorlandIDEServices as IOTAModuleServices).SaveAll;
            // If all files are saved none are left modified (some *.dfm files were still counted as being modified)
            ModifiedFiles.Clear;
          end
          else if (Response = mrCancel) then
            Exit;

          Cmd := '/command:update /notempfile';
          if (index = SVN_UPDATE_REV) then
            Cmd := Cmd + ' /rev';
          Cmd := Cmd + ' /path:' + AnsiQuotedStr( GetPathForProject(Project), '"');

          TSVNExec(Cmd);
        end;
      end else
      begin
        {
          The call is from the Popup and a file is selected
        }
        Cmd := '/command:update /notempfile';
        if (index = SVN_UPDATE_REV) then
          Cmd := Cmd + ' /rev';
        Cmd := Cmd + ' /path:' + AnsiQuotedStr(CmdFiles, '"');

        TSVNExec(Cmd);
      end;
    SVN_BLAME:
      begin
        EndRev := -1;

        // Only get the first file, ignore additional files (like *.dfm)
        Files := TStringList.Create;
        try
          GetFiles(Files);
          CmdFiles := Files[0];
        finally
          Files.Free;
        end;

        {
          Try to get the current local revision.
          Starting TortoiseSVN 1.9 it's not possible anymore to pass -1 as the
          endrev-parameter.
          Could be a bug in TortoiseSVN but just to be sure try to use svn info
          and pass the current local revision.
        }
        if (SVNExe <> '') then
          EndRev := GetCurrentRevision(SVNExe, CmdFiles);

        GetFileVersion(TSVNPath, Major, Minor, Build);

        RevStr := '/startrev:1 /endrev:' + IntToStr(EndRev);
        if (Major = 1) and (Minor >= 9) then
        begin
          // TortoiseSVN 1.9.x installed, and svn.exe NOT installed
          if (EndRev = -1) then
          begin
            // Can't pass endrev:-1, so don't pass any parameter -> dialog is shown
            RevStr := '';
          end;
        end;

        {
          The call is from the Popup and a file is selected
        }
        Cmd := '/command:blame /notempfile ' + RevStr + ' /path:' + AnsiQuotedStr(CmdFiles, '"');

        Line := -1;

        SourceEditor := GetCurrentSourceEditor;
        if (IsPopup) and (Assigned(SourceEditor)) then
        begin
          if (SourceEditor.EditViewCount > 0) then
          begin
            try
              Line := SourceEditor.EditViews[0].Position.Row;
            except
              Line := -1;
            end;
          end;
        end;

        if (Line > -1) then
          Cmd := Cmd + ' /line:' + IntToStr(Line);

        TSVNExec(Cmd);
      end;
    SVN_COMMIT:
      if (not IsPopup) or (IsProject) then
      begin
        {
          If it's a project which is accessed via the popup menu, then that
          project needs to be loaded and not the popup of the current file
          in the editor.
        }
        if (IsProject) then
        begin
          Project := (BorlandIDEServices as IOTAProjectManager).GetCurrentSelection(FileName);
        end;
            
        if (Project <> nil) then
        begin
          Response := CheckModified(Project);
          
          if (Response = mrYes) then
          begin
            (BorlandIDEServices as IOTAModuleServices).SaveAll;
            // If all files are saved none are left modified (some *.dfm files were still counted as being modified)
            ModifiedFiles.Clear;
          end
          else if (Response = mrCancel) then
            Exit;

          TSVNExec( '/command:commit /notempfile /path:' + AnsiQuotedStr( GetPathForProject(Project), '"' ) );
        end;
      end else
      begin
        {
          The call is from the Popup and a file is selected
        }
        Cmd := '/command:commit /notempfile /path:' + AnsiQuotedStr(CmdFiles, '"');

        TSVNExec(Cmd);
      end;
    SVN_DIFF:
        // this verb is handled by its menu item
        ;
    SVN_REVERT:
      if (not IsPopup) or (IsProject) then
      begin
        {
          If it's a project which is accessed via the popup menu, then that
          project needs to be loaded and not the popup of the current file
          in the editor.
        }
        if (IsProject) then
        begin
          Project := (BorlandIDEServices as IOTAProjectManager).GetCurrentSelection(FileName);
        end;
            
        if (Project <> nil) then
          TSVNExec( '/command:revert /notempfile /path:' + AnsiQuotedStr( GetPathForProject(Project), '"' ) );
      end else
      begin
        {
          The call is from the Popup and a file is selected
        }
        Cmd := '/command:revert /notempfile /path:' + AnsiQuotedStr(CmdFiles, '"');

        TSVNExec(Cmd);
      end;
    SVN_REPOSITORY_BROWSER:
      if (not IsPopup) or (IsProject) then
      begin
        {
          If it's a project which is accessed via the popup menu, then that
          project needs to be loaded and not the popup of the current file
          in the editor.
        }
        if (IsProject) then
        begin
          Project := (BorlandIDEServices as IOTAProjectManager).GetCurrentSelection(FileName);
        end;

        if (Project <> nil) then
          TSVNExec( '/command:repobrowser /notempfile /path:' + AnsiQuotedStr( ExtractFilePath(project.GetFileName), '"' ) )
        else
          TSVNExec( '/command:repobrowser' );
      end;
    SVN_SETTINGS:
        TSVNExec( '/command:settings' );
    SVN_PLUGIN_PROJ_SETTINGS:
      begin
        FmProjectSettings := TFmProjectSettings.Create(nil);
        try
          if (IsProject) then
          begin
            Project := (BorlandIDEServices as IOTAProjectManager).GetCurrentSelection(FileName);
          end;
          FmProjectSettings.Project := Project;
          
          FmProjectSettings.ShowModal;
        finally
          FmProjectSettings.Free;
        end;
      end;
    SVN_ABOUT:
        TSVNExec( '/command:about' );
    SVN_ABOUT_PLUGIN:
    begin
      GetFileVersion(TSVNPath, Major, Minor, Build);

      About := Format(GetString(30), [VERSION]);

      if (Major > 0) then
      begin
        About := About +
                 #10 +
                 Format('TortoiseSVN: %d.%d.%d', [Major, Minor, Build]);
      end;

      MessageDlg(About, mtInformation, [mbClose], 0);
    end;
    SVN_EDIT_CONFLICT,
    SVN_CONFLICT_OK:
        // these verbs are handled by their menu item
        ;
    SVN_CREATE_PATCH:
      if (not IsPopup) or (IsProject) then
      begin
        {
          If it's a project which is accessed via the popup menu, then that
          project needs to be loaded and not the popup of the current file
          in the editor.
        }
        if (IsProject) then
        begin
          Project := (BorlandIDEServices as IOTAProjectManager).GetCurrentSelection(FileName);
        end;
            
        if (Project <> nil) then
          TSVNExec( '/command:createpatch /notempfile /path:' + AnsiQuotedStr( ExtractFilePath(Project.GetFileName), '"' ) );
      end else
      begin
        {
          The call is from the Popup and a file is selected
        }
        Cmd := '/command:createpatch /notempfile /path:' + AnsiQuotedStr(CmdFiles, '"');

        TSVNExec(Cmd);
      end;
    SVN_USE_PATCH:
      if (not IsPopup) or (IsProject) then
      begin
        {
          If it's a project which is accessed via the popup menu, then that
          project needs to be loaded and not the popup of the current file
          in the editor.
        }
        if (IsProject) then
        begin
          Project := (BorlandIDEServices as IOTAProjectManager).GetCurrentSelection(FileName);
        end;

        if (Project <> nil) then
          TSVNMergeExec( '/patchpath:' + AnsiQuotedStr( ExtractFilePath(Project.GetFileName), '"' ) );
      end;
    SVN_CLEAN:
      if (not IsPopup) or (IsProject) then
      begin
        {
          If it's a project which is accessed via the popup menu, then that
          project needs to be loaded and not the popup of the current file
          in the editor.
        }
        if (IsProject) then
        begin
          Project := (BorlandIDEServices as IOTAProjectManager).GetCurrentSelection(FileName);
        end;

        if (Project <> nil) then
          TSVNExec( '/command:cleanup /notempfile /path:' + AnsiQuotedStr( ExtractFilePath(Project.GetFileName), '"' ) )
      end;
    SVN_IMPORT:
        if (Project <> nil) then
          TSVNExec( '/command:import /notempfile /path:' + AnsiQuotedStr( ExtractFilePath(Project.GetFileName), '"' ) );
    SVN_CHECKOUT:
        if (Project <> nil) then
          TSVNExec( '/command:checkout /notempfile /path:' + AnsiQuotedStr( ExtractFilePath(Project.GetFileName), '"' ) )
        else
          TSVNExec( '/command:checkout /notempfile' );
  end;
end;

function TTortoiseSVN.FindMenu(Item: TComponent): TMenu;
begin
  if (Item = nil) then
  begin
    Result := nil;
    Exit;
  end;

  if (Item is TMenu) then
  begin
    Result := TMenu(Item);
    Exit;
  end else
    Result := FindMenu(Item.Owner);
end;

procedure TTortoiseSVN.UpdateAction( sender: TObject );
var action: TAction;
begin
  action:= sender as TAction;
  action.Enabled := getVerbState( action.tag ) = vsEnabled;
end;

procedure TTortoiseSVN.ExecuteAction( sender: TObject );
var action: TAction;
begin
  action:= sender as TAction;
  executeVerb( action.tag );
end;

function TTortoiseSVN.GetIDString: string;
begin
  result:= 'Subversion.TortoiseSVN';
end;

function TTortoiseSVN.GetName: string;
begin
  result:= 'TortoiseSVN add-in';
end;

function TTortoiseSVN.GetPathForProject(Project: IOTAProject): string;
var
  I: Integer;
  Path: TStringList;
  ModInfo: IOTAModuleInfo;
  FilePath: string;

  ///  <summary>
  ///  Removes all subdirectories so that only the root directories are given
  ///  to TortoiseSVN.
  ///  </summary>
  function RemoveSubdirs(List: TStringList): Boolean;
  var
    I, X: Integer;
    Dir1, Dir2: string;
  begin
    Result := False;
    for I := 0 to List.Count - 1 do
    begin
      Dir1 := List.Strings[I];

      // Remove also empty entries
      if (Dir1 = '') then
      begin
        List.Delete(I );
        Result := True;
        Exit;
      end;

      for X := 0 to List.Count - 1 do
      begin
        if (X = I) then Continue;

        Dir2 := List.Strings[X];

        if (Length(Dir2) > Length(Dir1)) then
        begin
          if (Copy(Dir2, 1, Length(Dir1)) = Dir1) then
          begin
            List.Delete(X);
            Result := True;
            Exit;
          end;
        end;
      end;
    end;
  end;

begin
  Path := TStringList.Create;
  try
    Path.Sorted := True;
    Path.Add(ExtractFilePath(Project.FileName));

    for I := 0 to Project.GetModuleCount - 1 do
    begin
      ModInfo := Project.GetModule(I);
      if (ModInfo.ModuleType <> omtPackageImport) and
         (ModInfo.ModuleType <> omtTypeLib) then
      begin
        FilePath := ExtractFilePath(ModInfo.FileName);
        if (Path.IndexOf(FilePath) = -1) then
          Path.Add(FilePath);
      end;
    end;

    Path.AddStrings(GetDirectoriesFromTSVN(Project));

    while (RemoveSubdirs(Path)) do;

    Result := '';
    for I := 0 to Path.Count - 1 do
    begin
      Result := Result + Path.Strings[I];
      if (I < Path.Count - 1) then
        Result := Result + '*';
    end;
  finally
    Path.Free;
  end;
end;

function TTortoiseSVN.GetState: TWizardState;
begin
  result:= [wsEnabled];
end;

procedure TTortoiseSVN.Execute;
begin
  // empty
end;

{$IFNDEF DLL_MODE}

procedure Register;
begin
  RegisterPackageWizard(TTortoiseSVN.create);
end;

{$ELSE}

var wizardID: integer;

procedure FinalizeWizard;
var
  WizardServices: IOTAWizardServices;
begin
  Assert(Assigned(BorlandIDEServices));

  WizardServices := BorlandIDEServices as IOTAWizardServices;
  Assert(Assigned(WizardServices));

  WizardServices.RemoveWizard(wizardID);
end;

function InitWizard(const BorlandIDEServices: IBorlandIDEServices;
  RegisterProc: TWizardRegisterProc;
  var Terminate: TWizardTerminateProc): Boolean; stdcall;
var
  WizardServices: IOTAWizardServices;
begin
  Assert(BorlandIDEServices <> nil);
  Assert(ToolsAPI.BorlandIDEServices = BorlandIDEServices);

  Terminate := FinalizeWizard;

  WizardServices := BorlandIDEServices as IOTAWizardServices;
  Assert(Assigned(WizardServices));

  wizardID:= WizardServices.AddWizard(TTortoiseSVN.Create as IOTAWizard);

  result:= wizardID >= 0;
end;


exports
  InitWizard name WizardEntryPoint;

{$ENDIF}

{ TIdeNotifier }

procedure TIdeNotifier.AfterCompile(Succeeded: Boolean);
begin
  // empty
end;

procedure TIdeNotifier.BeforeCompile(const Project: IOTAProject;
  var Cancel: Boolean);
begin
  // empty
end;

procedure TIdeNotifier.Destroyed;
begin
  WriteDebug('TIdeNotifier.Destroyed');

  inherited;
end;

function IsProjectFile(const FileName: string; var Project: IOTAProject): Boolean;
var
  Module  : IOTAModule;
  ProjectGroup : IOTAProjectGroup;
begin
  Module := (BorlandIDEServices as IOTAModuleServices).FindModule(FileName);
  Result := Supports(Module, IOTAProject, Project) and
            not Supports(Module, IOTAProjectGroup, ProjectGroup);
end;

procedure TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
var
  Project  : IOTAProject;
  Module   : IOTAModule;
  I, Index : Integer;
  Notifier : TProjectNotifier;
begin
  WriteDebug('TIdeNotifier.FileNotification :: start');
  case NotifyCode of
    ofnFileOpened:
    begin
      if IsProjectFile(FileName, Project) then
      begin
        Notifier := TProjectNotifier.Create(FileName);
        Notifier.Project := Project;
        Notifier.ModuleCount := Project.GetModuleFileCount;
        for I := 0 to Notifier.ModuleCount - 1 do
        begin
          Notifier.Module[I] := Project.ModuleFileEditors[I].Module;
        end;

        Index := Project.AddNotifier(Notifier as IOTAProjectNotifier);
        if (Index >= 0) then
          NotifierList.AddObject(FileName, Pointer(Index));
      end else
      begin
        Module := (BorlandIDEServices as IOTAModuleServices).FindModule(FileName);
        if not Assigned(Module) then Exit;

        RegisterPopup(Module);
        
        RegisterEditorNotifier(Module);
      end;
    end;
    ofnProjectDesktopLoad:
    begin
      // FileName = *.dsk
      for I := 0 to (BorlandIDEServices as IOTAModuleServices).ModuleCount - 1 do
      begin
        Module := (BorlandIDEServices as IOTAModuleServices).Modules[I];

        RegisterPopup(Module);

        RegisterEditorNotifier(Module);
      end;
    end;
    ofnFileClosing :
    begin
      Module := (BorlandIDEServices as IOTAModuleServices).FindModule(FileName);
      if (not Assigned(Module)) then Exit;

      if NotifierList.Find(FileName, I) then
      begin
        Index := Integer(NotifierList.Objects[I]);
        NotifierList.Delete(I);
        Module.RemoveNotifier(Index);
      end;

      RemoveEditorNotifier(Module);

      // If a project is closed, remove all the modified files from the list
      if IsProjectFile(FileName, Project) then
      begin
        ModifiedFiles.Clear;
      end;
    end;
  end;

  WriteDebug('TIdeNotifier.FileNotification :: done');
end;


class function TIdeNotifier.RegisterPopup(Module: IOTAModule): Boolean;
var
  I, K: Integer;
  Editor: IOTAEditor;
  SourceEditor: IOTASourceEditor;
begin
  WriteDebug('TIdeNotifier.RegisterPopup :: start');

  Result := False;

  for I := 0 to Module.GetModuleFileCount - 1 do
  begin
    Editor := nil;
    try
      Editor := Module.GetModuleFileEditor(I);
    except
    end;

    if Assigned(Editor) and Supports(Editor, IOTASourceEditor, SourceEditor) then
    begin
      for K := 0 to SourceEditor.EditViewCount - 1 do
      begin
        Result := RegisterPopup(SourceEditor.EditViews[K]);
        if (Result) then Exit;
      end;
    end;
  end;

  WriteDebug('TIdeNotifier.RegisterPopup :: done');
end;

class procedure TIdeNotifier.RegisterEditorNotifier(Module: IOTAModule);
var
  I: Integer;
  Editor: IOTAEditor;
  EditorNotifier: TEditorNotifier;
  SourceEditor: IOTASourceEditor;
begin
  WriteDebug('TIdeNotifier.RegisterEditorNotifier :: start');

  for I := 0 to Module.GetModuleFileCount - 1 do
  begin
    Editor := nil;
    try
      Editor := Module.GetModuleFileEditor(I);
    except
    end;

    if (Assigned(Editor)) then
    begin
      if (EditorNotifierList.IndexOf(Editor.FileName) = -1) then
      begin
        EditorNotifier := TEditorNotifier.Create(Editor);
        if (Supports(Editor, IOTASourceEditor, SourceEditor)) then
        begin
          {
            It can happen that no view is reported at this time so we need
            to add the entry for the popup menu in the editor at a later time.
          }
          if (SourceEditor.EditViewCount = 0) then
            EditorNotifier.Opened := False;
        end;
        
        EditorNotifierList.AddObject(Editor.FileName, EditorNotifier);
      end;
    end;
  end;

  WriteDebug('TIdeNotifier.RegisterEditorNotifier :: done');
end;

class function TIdeNotifier.RegisterPopup(View: IOTAEditView): Boolean;
var
  EditWindow: INTAEditWindow;
  Frm: TCustomForm;
begin
  WriteDebug('TIdeNotifier.RegisterPopup :: start');

  if (EditPopup = nil) then
  begin
    try
      EditWindow := View.GetEditWindow;
      if (not Assigned(EditWindow)) then
        Exit;

      Frm := EditWindow.Form;
      if (not Assigned(Frm)) then
        Exit;

      EditPopup := (Frm.FindComponent('EditorLocalMenu') as TPopupMenu);

      if not Assigned(EditorMenuPopupListener) then
        EditorMenuPopupListener := TEditorMenuPopupListener.Create;

      EditorMenuPopupListener.RegisterPopup(EditPopup);
    except
    end;
  end;

  Result := True;
end;

class procedure TIdeNotifier.RemoveEditorNotifier(Module: IOTAModule);
var
  Editor: IOTAEditor;
  I, Idx: Integer;
  EditorNotifier: TEditorNotifier;
begin
  try
    WriteDebug(Format('TIdeNotifier.RemoveEditorNotifier (%s) :: start', [Module.FileName]));
  except
  end;

  for I := 0 to Module.GetModuleFileCount - 1 do
  begin
    WriteDebug(Format('TIdeNotifier.RemoveEditorNotifier :: %d', [I]));
    Editor := nil;
    try
      Editor := Module.GetModuleFileEditor(I);
    except
    end;

    if (Assigned(Editor)) then
    begin
      try
        if (EditorNotifierList.Find(Editor.FileName, Idx)) then
        begin
          EditorNotifier := TEditorNotifier(EditorNotifierList.Objects[Idx]);
          EditorNotifierList.Delete(Idx);
          EditorNotifier.RemoveBindings;
        end;
      except
      end;
    end;
  end;

  try
    WriteDebug(Format('TIdeNotifier.RemoveEditorNotifier (%s) :: done', [Module.FileName]));
  except
  end;
end;

{ TProjectNotifier }

constructor TProjectNotifier.Create(const FileName: string);
begin
  inherited Create;

  FFileName := FileName;
end;

procedure TProjectNotifier.Destroyed;
begin
  WriteDebug('TProjectNotifier.Destroyed');

  inherited;
end;

function TProjectNotifier.GetModule(Index: Integer): IOTAModule;
begin
  Result := FModules[Index];
end;

procedure TProjectNotifier.ModuleRenamed(const AOldFileName,
  ANewFileName: string);
var
  I, Index : Integer;
  EditorNotifier: TEditorNotifier;
  ModuleNotifier: TModuleNotifier;
  Idx: Integer; 
begin
  WriteDebug(Format('TProjectNotifier.ModuleRenamed ("%s" to "%s")', [AOldFileName, ANewFileName]));

  if NotifierList.Find(AOldFileName, I) then
  begin
    WriteDebug(Format('NotifierList Index: %d', [I]));
    Index := Integer(NotifierList.Objects[I]);
    NotifierList.Delete(I);
    NotifierList.AddObject(ANewFileName, Pointer(Index));
  end;

  if ModuleNotifierList.Find(AOldFileName, I) then
  begin
    WriteDebug(Format('ModuleNotifierList Index: %d', [I]));
    ModuleNotifier := TModuleNotifier(ModuleNotifierList.Objects[I]);
    ModuleNotifier.FileName := ANewFileName;
    ModuleNotifierList.Delete(I);
    ModuleNotifierList.AddObject(ANewFileName, ModuleNotifier);
  end;

  if EditorNotifierList.Find(AOldFileName, I) then
  begin
    WriteDebug(Format('EditorNotifierList Index: %d', [I]));
    EditorNotifier := TEditorNotifier(EditorNotifierList.Objects[I]);
    EditorNotifierList.Delete(I);
    EditorNotifierList.AddObject(ANewFileName, EditorNotifier);
  end;

  // The file is renamed (and saved), so the old one is no longer part of the
  // project and should therefore no longer be treated as "modified".
  WriteDebug(Format('"%s" renamed, removing from "modified list"', [AOldFileName]));
  if (ModifiedFiles.Find(AOldFileName, Idx)) then
    ModifiedFiles.Delete(Idx);

  FFileName := ANewFileName;
end;

procedure TProjectNotifier.ModuleRenamed(const NewName: string);
begin
  WriteDebug(Format('TProjectNotifier.ModuleRenamed (%s)', [NewName]));
  ModuleRenamed(FFileName, NewName);
end;

procedure RemoveIDENotifier;
var
  Services : IOTAServices;
begin
  WriteDebug('RemoveIDENotifier :: start');
  if IDENotifierIndex > -1 then
  begin
    Services := BorlandIDEServices as IOTAServices;
    Assert(Assigned(Services), 'IOTAServices not available');
    Services.RemoveNotifier(IDENotifierIndex);
    IDENotifierIndex := -1;
  end;
  WriteDebug('RemoveIDENotifier :: done');
end;

procedure FinalizeNotifiers;
var
  I, Index : Integer;
  ModServices : IOTAModuleServices;
  Module : IOTAModule;
begin
  WriteDebug('FinalizeNotifiers :: start');
  if not Assigned(NotifierList) then Exit;
  ModServices := BorlandIDEServices as IOTAModuleServices;

  try
    Assert(Assigned(ModServices), 'IOTAModuleServices not available');

    for I := 0 to NotifierList.Count -1 do
    begin
      WriteDebug(Format('FinalizeNotifiers :: Notifier %d / %d', [I+1, NotifierList.Count]));

      Index := Integer(NotifierList.Objects[I]);
      Module := ModServices.FindModule(NotifierList[I]);
      if Assigned(Module) then
      begin
        Module.RemoveNotifier(Index);
      end;
    end;
  finally
    FreeAndNil(NotifierList);
  end;
  WriteDebug('FinalizeNotifiers :: done');
end;

procedure FinalizeEditorNotifiers;
var
  I : Integer;
  EditorNotifier: TEditorNotifier;
begin
  WriteDebug('FinalizeEditorNotifiers :: start');
  if not Assigned(EditorNotifierList) then Exit;

  try
    for I := 0 to EditorNotifierList.Count -1 do
    begin
      WriteDebug(Format('FinalizeEditorNotifiers :: Notifier %d / %d', [I+1, EditorNotifierList.Count]));

      EditorNotifier := TEditorNotifier(EditorNotifierList.Objects[I]);
      EditorNotifier.RemoveBindings;
      try
        EditorNotifier.Free;
      except
      end;
    end;
  finally
    FreeAndNil(EditorNotifierList);
  end;
  WriteDebug('FinalizeEditorNotifiers :: done');
end;

procedure TProjectNotifier.SetModule(Index: Integer; const Value: IOTAModule);
begin
  FModules[Index] := Value;
end;

procedure TProjectNotifier.SetModuleCount(const Value: Integer);
begin
  FModuleCount := Value;
  SetLength(FModules, FModuleCount);
end;

procedure TProjectNotifier.ModuleAdded(const AFileName: string);
var
  ModInfo: IOTAModuleInfo;
  Module: IOTAModule;
begin
  WriteDebug(Format('TProjectNotifier.ModuleAdded (%s)', [AFileName]));

  {
    After adding the module, register a notifier to check for changes on the file
    and be able to ask if the file should be added to the SVN.
  }
  ModInfo := FProject.FindModuleInfo(AFileName);
  if (ModInfo <> nil) then
  begin
    Module := ModInfo.OpenModule;
    ModuleNotifierList.AddObject(AFileName, TModuleNotifier.Create(AFileName, Module));
  end;
end;

procedure TProjectNotifier.ModuleRemoved(const AFileName: string);
var
  Cmd: string;
  Idx: Integer;
  ModuleNotifier: TModuleNotifier;
begin
  WriteDebug(Format('TProjectNotifier.ModuleRemoved (%s)', [AFileName]));

  // If a module is removed from the project also remove the module notifier
  if (ModuleNotifierList.Find(AFileName, Idx)) then
  begin
    WriteDebug(Format('Index: %d', [Idx]));
    
    ModuleNotifier := TModuleNotifier(ModuleNotifierList.Objects[Idx]);
    ModuleNotifierList.Delete(Idx);
    ModuleNotifier.RemoveBindings;
  end;

  if (MessageDlg(Format(GetString(29), [ExtractFileName(AFileName)]), mtConfirmation, [mbYes,mbNo], 0) <> mrYes) then
    Exit;

  // TODO : Files already dismissed after remove?
  Cmd := '/command:remove /notempfile /path:' + AnsiQuotedStr(GetFilesForCmd(FProject, AFileName), '"');

  TTortoiseSVN.TSVNExec(Cmd);
end;

{ TModuleNotifier }

procedure TModuleNotifier.AfterSave;
var
  I: Integer;
  Cmd: string;
  FileList: TStringList;
begin
  if (MessageDlg(Format(GetString(28), [ExtractFileName(_Filename)]), mtConfirmation, [mbYes,mbNo], 0) <> mrYes) then
  begin
    {
      Always remove notifier after asking for adding the file and don't ask
      every time a file is saved.
    }
    RemoveBindings;

    Exit;
  end;

  Cmd := '';
  FileList := TStringList.Create;
  try
    GetModuleFiles(FileList, _Module);

    for I := 0 to FileList.Count - 1 do
    begin
      Cmd := Cmd + FileList[I];
      if (I < FileList.Count - 1) then
        Cmd := Cmd + '*';
    end;
  finally
    FileList.Free;
  end;

  Cmd := '/command:add /notempfile /path:' + AnsiQuotedStr(Cmd, '"');

  TTortoiseSVN.TSVNExec(Cmd);

  RemoveBindings;
end;

constructor TModuleNotifier.Create(Filename: string; Module: IOTAModule);
begin
  inherited Create;

  _Filename := Filename;
  _Module := Module;
  _Notifier := _Module.AddNotifier(Self);
end;

destructor TModuleNotifier.Destroy;
begin
  WriteDebug(Format('TModuleNotifier.Destroy (%s)', [_Module.FileName]));
  RemoveBindings;

  inherited Destroy;
end;

procedure TModuleNotifier.Destroyed;
begin
  WriteDebug('TModuleNotifier.Destroyed');
  RemoveBindings;

  inherited;
end;

procedure TModuleNotifier.RemoveBindings;
var
  Notifier: Integer;
begin
  if (_Module = nil) then
  begin
    _Notifier := -1;
    Exit;
  end;

  WriteDebug(Format('TModuleNotifier.RemoveBindings (%s)', [_Module.FileName]));

  Notifier := _Notifier;
  _Notifier := -1;

  try
    if (Notifier <> -1) then
    begin
      WriteDebug(Format('Removing Notifier %d', [Notifier]));
      _Module.RemoveNotifier(Notifier);
    end;
  except
  end;

  WriteDebug('TModuleNotifier.RemoveBindings :: done');
end;

{ TProjectMenuTimer }

constructor TProjectMenuTimer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  Self.OnTimer := Self.TimerTick;
  Self.Interval := 1;
  Self.Enabled := True;
end;

procedure TProjectMenuTimer.TimerTick(Sender: TObject);
var
  I: Integer;
  Item: TMenuItem;
begin
  Self.Enabled := False;

  if (Owner is TMenuItem) then
  begin
    for I := 0 to TMenuItem(Owner).Count - 1 do
    begin
      Item := TMenuItem(Owner).Items[I];
      if (Item.Tag = SVN_DIFF) or
         (Item.Tag = SVN_LOG_FILE) or
         (Item.Tag = SVN_EDIT_CONFLICT) or
         (Item.Tag = SVN_CONFLICT_OK) then
      begin
        if (Item.ImageIndex = -1) and
           (Item.GetImageList <> nil) then
        begin
          if (ImgIdx[Item.Tag] = -1) then
            ImgIdx[Item.Tag] := Item.GetImageList.AddMasked(Bitmaps[Item.Tag], clBlack);
          Item.ImageIndex := ImgIdx[Item.Tag];
        end;
      end;
    end;
  end;

  TortoiseSVN.ProjectMenuTimer.Free;
  TortoiseSVN.ProjectMenuTimer := nil;
end;

{ TEditorNotifier }

procedure TEditorNotifier.AfterSave;
var
  Idx: Integer;
  I: Integer;
begin
  WriteDebug('TEditorNotifier.AfterSave :: start');

  // If a file (*.pas) is saved, the corresponding files (*.dfm) are also saved
  // so it's safe to remove them from the list
  for I := 0 to _Editor.Module.ModuleFileCount - 1 do
  begin
    if (ModifiedFiles.Find(_Editor.Module.ModuleFileEditors[I].FileName, Idx)) then
      ModifiedFiles.Delete(Idx);
  end;

  WriteDebug('TEditorNotifier.AfterSave :: done');
end;

constructor TEditorNotifier.Create(const Editor: IOTAEditor);
begin
  inherited Create;

  _Editor := Editor;
  _Opened := True;
  _Notifier := _Editor.AddNotifier(Self as IOTAEditorNotifier);
end;

destructor TEditorNotifier.Destroy;
begin
  WriteDebug(Format('TEditorNotifier.Destroy (%s)', [_Editor.FileName]));
  RemoveBindings;

  inherited;
end;

procedure TEditorNotifier.Destroyed;
begin
  WriteDebug(Format('TEditorNotifier.Destroyed (%s)', [_Editor.FileName]));
  RemoveBindings;

  inherited;
end;

procedure TEditorNotifier.Modified;
begin
  if (ModifiedFiles.IndexOf(_Editor.FileName) = -1) then
    ModifiedFiles.Add(_Editor.FileName);
end;

procedure TEditorNotifier.RemoveBindings;
var
  Notifier: Integer;
begin
  WriteDebug(Format('TEditorNotifier.RemoveBindings (%s)', [_Editor.FileName]));
  
  Notifier := _Notifier;
  _Notifier := -1;

  if (Notifier <> -1) then
  begin
    try
      WriteDebug(Format('Removing Notifier %d', [Notifier]));
      _Editor.RemoveNotifier(Notifier);
    except
    end;
  end;

  WriteDebug('TEditorNotifier.RemoveBindings :: done');
end;

procedure TEditorNotifier.ViewActivated(const View: IOTAEditView);
begin
  // not used
end;

procedure TEditorNotifier.ViewNotification(const View: IOTAEditView;
  Operation: TOperation);
begin
  {
    It can happen that no view is reported while registering the popup the first
    time so we need to check the view notification and add the popup afterwards.
  }
  if (not _Opened) and (Operation = opInsert) then
  begin
    _Opened := True;
    TIdeNotifier.RegisterPopup(View);
  end;
end;

procedure RegisterAboutBox;
var
  //ProductImage: HBITMAP;
  AboutBoxServices: IOTAAboutBoxServices;
begin
  if (Supports(BorlandIDEServices,IOTAAboutBoxServices, AboutBoxServices)) then
  begin
    // ProductImage := LoadBitmap(FindResourceHInstance(HInstance), 'JVCLSPLASH');
    AboutBoxIndex := AboutBoxServices.AddPluginInfo(
                        Format('TortoiseSVN Plugin %s', [VERSION]),
                        Format('TortoiseSVN Plugin %s', [VERSION]) + #13#10 +
                        'http://sourceforge.net/projects/delphitsvnaddin/' + #13#10 +
                        'Licensed under LGPL 3.0 or later' + #13#10 +
                        'License http://www.gnu.org/licenses/lgpl-3.0.txt',
                        0, False, 'LGPL 3.0');
  end;
end;

procedure UnregisterAboutBox;
var
  AboutBoxServices: IOTAAboutBoxServices;
begin
  if (AboutBoxIndex <> -1) and Supports(BorlandIDEServices,IOTAAboutBoxServices, AboutBoxServices) then
  begin
    AboutBoxServices.RemovePluginInfo(AboutBoxIndex);
    AboutBoxIndex := -1;
  end;
end;


{ TEditorMenuPopupListener }

destructor TEditorMenuPopupListener.Destroy;
begin
  try
    Remove;
  finally
    inherited;
  end;
end;

procedure TEditorMenuPopupListener.MenuPopup(Sender: TObject);
{$IFDEF UseVersionMenu}
var
  I: Integer;
{$ENDIF}
begin
  EditPopup := TPopupMenu(Sender);

  // Always clear the items first, then add yourself again
  EditPopup.Items.Clear;

  // Delphis original popup listener adds all the items back again
  if Assigned(FOldPopupListener) then
    FOldPopupListener(Sender);

{$IFDEF UseVersionMenu}
  for I := 0 to EditPopup.Items.Count - 1 do
  begin
    if (EditPopup.Items[I].Name = 'VersionControlAction') then
    begin
      VersionControlMenuPopup := EditPopup.Items[I];
      Break;
    end;
  end;
{$ENDIF}


{$IFDEF UseVersionMenu}
  if Assigned(VersionControlMenuPopup) then
    EditMenuItem := TMenuItem.Create(VersionControlMenuPopup)
  else
{$ENDIF}
    EditMenuItem := TMenuItem.Create(EditPopup);

  EditMenuItem := TMenuItem.Create(EditPopup);
  EditMenuItem.Name := 'TortoiseSVNPopupMenuEntry';
  EditMenuItem.Caption := 'TortoiseSVN';
  EditMenuItem.Visible := True;
  EditMenuItem.Tag := 4 or 1;
  EditMenuItem.OnClick := TortoiseSVN.TSVNMenuClick;

  TortoiseSVN.CreateMenu(EditMenuItem, sFileContainer);

{$IFDEF UseVersionMenu}
  if Assigned(VersionControlMenuPopup) then
    VersionControlMenuPopup.Add(EditMenuItem)
  else
{$ENDIF}
    EditPopup.Items.Add(EditMenuItem);
end;

procedure TEditorMenuPopupListener.RegisterPopup(const APopup: TPopupMenu);
begin
  Remove;

  FPopup := APopup;

  FOldPopupListener := FPopup.OnPopup;
  FPopup.OnPopup := Self.MenuPopup;
end;

procedure TEditorMenuPopupListener.Remove;
var
  MyPopup: TNotifyEvent;
begin
  // Remove self from current popup menu if assigned
  if Assigned(FPopup) then
  begin
    try
      MyPopup := MenuPopup;
      if (@FPopup.OnPopup = @MyPopup) then
      begin
        FPopup.OnPopup := FOldPopupListener;
        FOldPopupListener := nil;
      end;
    except
    end;
  end;
end;

initialization
  WriteDebug('initialization ' + DateTimeToStr(Now));
  NotifierList := TStringList.Create;
  NotifierList.Sorted := True;
  EditorNotifierList := TStringList.Create;
  EditorNotifierList.Sorted := True;
  ModifiedFiles := TStringList.Create;
  ModifiedFiles.Sorted := True;
  ModuleNotifierList := TStringList.Create;
  ModuleNotifierList.Sorted := True;
  RegisterAboutBox;

finalization
  WriteDebug('finalization ' + DateTimeToStr(Now));

  try
    WriteDebug('Should I remove the MenuCreatorNotifier?');
    if (MenuCreatorNotifier <> -1) then
    begin
      WriteDebug('Yes, I should!');
      (BorlandIDEServices as IOTAProjectManager).RemoveMenuCreatorNotifier(MenuCreatorNotifier);
    end else
    begin
      WriteDebug('Nope!');
    end;
  except
  end;

  try
    RemoveIDENotifier;
  except
  end;

  try
    FinalizeNotifiers;
  except
  end;

  try
    FinalizeEditorNotifiers;
  except
  end;

  try
    WriteDebug('FreeAndNil(ModifiedFiles)');
    FreeAndNil(ModifiedFiles);
  except
  end;

  try
    WriteDebug('FreeAndNil(ModuleNotifierList)');
    FreeAndNil(ModuleNotifierList);
  except
  end;

  try
    WriteDebug('Should I remove the EditMenuItem?');
    EditorMenuPopupListener := nil;

    if (EditMenuItem <> nil) then
    begin
      WriteDebug('Possibly!');

{$IFDEF UseVersionMenu}
      if (Assigned(VersionControlMenuPopup)) and
         (VersionControlMenuPopup.IndexOf(EditMenuItem) > -1) then
      begin
        WriteDebug('Yes, I should!');
        VersionControlMenuPopup.Remove(EditMenuItem);
        EditMenuItem := nil;
      end
      else
{$ENDIF}
      if (EditPopup <> nil) and
         (EditPopup.Items.IndexOf(EditMenuItem) > -1) then
      begin
        WriteDebug('Yes, I should!');
        EditPopup.Items.Remove(EditMenuItem);
        EditPopup := nil;
      end
      else
      begin
        WriteDebug('Nope!');
      end;
    end;
  except
  end;

  try
    WriteDebug('Should I free the EditMenuItem?');

    // Only remove if it's ours
    if (EditMenuItem <> nil) and (EditMenuItem.Name = 'TortoiseSVNPopupMenuEntry') then
    begin
      WriteDebug('Yes, I should!');
      EditMenuItem.Free;
      EditMenuItem := nil;
    end else
    begin
      WriteDebug('Nope!');
    end;
  except
  end;

  try
    UnRegisterAboutBox;
  except
  end;
end.

