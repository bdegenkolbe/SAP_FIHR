--Declare @Datenweg as int; Execute dbo.Konfiguration @Datenweg=@Datenweg
Create or Alter Proc dbo.Konfiguration 
		@SQL_TableTargetDB nvarchar(200)='Analysen',
		@SQL_TableTargetSchema nvarchar(200)='dbo',
		@SQL_TableLoggingString nvarchar(200),
		@SQL_TableTabStatusString nvarchar(200),
		@SQL_TableQlikLoadString nvarchar(200),
		@SQL_TableRelationTreeString nvarchar(200),
		@Datenweg int Output
	AS
	BEGIN
		Declare @SQL as nvarchar(max)
		Declare @SQL1 as nvarchar(max)
		Declare @SQL2 as nvarchar(max)
		Declare @SQL3 as nvarchar(max)
		Declare @SQL4 as nvarchar(max)
		Declare @SQL5 as nvarchar(max)
		Declare @SQL6 as nvarchar(max)
		Declare @SQL7 as nvarchar(max)
		Declare @SQL8 as nvarchar(max)
		Declare @SQL9 as nvarchar(max)
		Declare @SQL10 as nvarchar(max)

		If LEN(@SQL_TableTargetDB)=0
			SET @SQL_TableTargetDB = 'Analysen'

		If LEN(@SQL_TableTargetSchema)=0
			SET @SQL_TableTargetSchema = 'dbo'

		If LEN(@SQL_TableLoggingString)=0
			SET @SQL_TableLoggingString = concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_Log')

		If LEN(@SQL_TableTabStatusString)=0
			SET @SQL_TableTabStatusString = concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_TabStatus')

		If LEN(@SQL_TableQlikLoadString)=0
			SET @SQL_TableQlikLoadString = concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_QlikLoad')

		If LEN(@SQL_TableRelationTreeString)=0
			SET @SQL_TableRelationTreeString = concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_TabTree')

		Set @SQL=concat('Use ',@SQL_TableTargetDB)
		Exec (@SQL)
		SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''; SET @SQL4=''; SET @SQL5=''; SET @SQL6='' 	
		
		Set @Datenweg=0
		IF OBJECT_ID(@SQL_TableLoggingString, 'U') IS NULL 
			Begin
				--drop table Analysen.dbo.Admin_Log
				--Select *,object_id(LogTableName,'U') as LogObjectID into Analysen.dbo.Admin_Log_Backup from Analysen.dbo.Admin_Log
				--Select * from Analysen.dbo.Admin_Log
				SET @SQL=Concat('Create Table ',@SQL_TableLoggingString,'
									(LogID				bigint			not null,
									LogTableName		nvarchar(200)	not null,
									LogObjectID			bigint			null,
									LogTableTime		DateTime2		null,
									LogTableProcess			nvarchar(200)	null, --Update/Join...
									LogTableProcessMode		nvarchar (50)	null, --FULL/DELTA/TEST/PREPARING
									LogTableProcessStatus	nvarchar (50)	null, --PROCESS/FINISHED/ERROR

									LogStep				nvarchar(50)	null,
									LogStepText			nvarchar(500)	null,
									LogStepStart		DateTime2		null default Getdate(),
									LogStepEnd			DateTime2		null default Getdate(),
									LogStepDuration		time(0)			null,
									LogStepDuration_cum	time(0)			null,
									LogStepSQL			ntext			null,
									LogStepRows			bigint			null,
									LogStepStatus		nvarchar(20)	null, --PROCESS/FINISHED/ERROR
									LogStepError		int				null, --Error-Code
									LogStepErrorText	nvarchar(4000)	null, --Error-Text

									LogTime				DateTime2		not null default Getdate(),
									LogUser				nvarchar(100)	not null default SUSER_SNAME())');

				EXEC(@SQL);
				SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''; SET @SQL4=''; SET @SQL5=''; SET @SQL6='' 	

				SET @Datenweg=1;
			end

		IF OBJECT_ID(@SQL_TableTabStatusString, 'U') IS NULL 
			Begin
				--drop table Analysen.dbo.Admin_TabStatus
				SET @SQL=Concat('Create Table ',@SQL_TableTabStatusString,'
									(StatusTable		varchar(500)	not null,
									StatusInfo			varchar(100)	not null,
									StatusTime			DateTime2		not null default Getdate(),
									StatusText			varchar(500)	null)');

				EXEC(@SQL);
				SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''; SET @SQL4=''; SET @SQL5=''; SET @SQL6='' ;		
			end

		IF OBJECT_ID(@SQL_TableRelationTreeString, 'U') IS NULL 
			Begin
				--drop table Analysen.dbo.Admin_TabTree
				SET @SQL=Concat('
								Create Table ',@SQL_TableRelationTreeString,'
									(RelationID			bigint			not null,

									TargetTableDB		varchar(200)	not null,
									TargetTableSchema	varchar(200)	not null,
									TargetTableName		varchar(200)	not null,
									TargetObjectID		bigint			not null,
									TargetID			varchar(200)	not null,
									TargetRowID			varchar(200)	not null,
									TargetUpdate		DateTime2		not null default Getdate(),
									TargetRows			bigint			null,
									TargetSpace			bigint			null,

									SourceTableDB		varchar(200)	not null,
									SourceTableSchema	varchar(200)	not null,
									SourceTableName		varchar(200)	not null,
									SourceObjectID		bigint			not null,
									SourceID			varchar(200)	not null,
									SourceRowID			varchar(200)	null,
									SourceUpdate		DateTime2		not null default Getdate(),
									
									QlikLoad			varchar(max)	null,
									Konfig				varchar(max)	null,
									LastChangeOnDate	int				null,
									StatusText			varchar(500)	null,

									LoadingMethode		varchar(20)		not null,
									LogID				bigint			not null,
									LoggingTable		varchar(500)	not null,
									
									)									
									');
								
				EXEC(@SQL);
				SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''; SET @SQL4=''; SET @SQL5=''; SET @SQL6='' ;
			end

		Set @SQL=Concat('','
		CREATE or Alter FUNCTION dbo.TableString_decompose
		(	
			@TableString nvarchar(500), 
			@Part int
		)
		RETURNS nvarchar(500)
		AS
		BEGIN

			DECLARE @a as int
			DECLARE @b as int
			DECLARE @c as nvarchar(500)

			Set @a=charindex(''.'',@TableString)
			Set @b=charindex(''.'',@TableString,@a+1)

			if @Part=1 
				SET @c=left(@TableString,@a-1)

			if @Part=2 
				SET @c=substring(@TableString,@a+1,@b-@a-1)

			if @Part=3 
				SET @c=right(@TableString,len(@TableString)-@b)

			RETURN @c

		END
		')

		Exec (@SQL)
		SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''; SET @SQL4=''	

		Set @SQL=Concat('','
		create or ALTER FUNCTION dbo.CleanAndTrim (
			@Str NVARCHAR(MAX)
			, @ReplaceTabWith NVARCHAR(5) = '' ''
			, @ReplaceNewlineWith NVARCHAR(5) = '' ''
			, @PurgeReplaceCharsAtEnds BIT = 1
		)
		RETURNS NVARCHAR(MAX) AS
		BEGIN
			DECLARE @Result NVARCHAR(MAX)

			SET @Result = LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
				LTRIM(RTRIM(@Str))  --Basic trim
				, NCHAR(9), @ReplaceTabWith), NCHAR(11), @ReplaceTabWith)   --Replace tab & vertical-tab
				, (NCHAR(13) + NCHAR(10)), @ReplaceNewlineWith) --Replace "Windows" linebreak (CR+LF)
				, NCHAR(10), @ReplaceNewlineWith), NCHAR(12), @ReplaceNewlineWith), NCHAR(13), @ReplaceNewlineWith)
				,'' '',@ReplaceTabWith)))   --Replace other newlines

			IF (@PurgeReplaceCharsAtEnds = 1 AND NOT (@ReplaceTabWith = N'' '' AND @ReplaceNewlineWith = N'' ''))
			BEGIN

				WHILE (LEFT(@Result, DATALENGTH(@ReplaceTabWith)/2) = @ReplaceTabWith)
					SET @Result = SUBSTRING(@Result, DATALENGTH(@ReplaceTabWith)/2 + 1, DATALENGTH(@Result)/2)

				WHILE (LEFT(@Result, DATALENGTH(@ReplaceNewlineWith)/2) = @ReplaceNewlineWith)
					SET @Result = SUBSTRING(@Result, DATALENGTH(@ReplaceNewlineWith)/2 + 1, DATALENGTH(@Result)/2)

				WHILE (RIGHT(@Result, DATALENGTH(@ReplaceTabWith)/2) = @ReplaceTabWith)
					SET @Result = SUBSTRING(@Result, 1, DATALENGTH(@Result)/2 - DATALENGTH(@ReplaceTabWith)/2)

				WHILE (RIGHT(@Result, DATALENGTH(@ReplaceNewlineWith)/2) = @ReplaceNewlineWith)
					SET @Result = SUBSTRING(@Result, 1, DATALENGTH(@Result)/2 - DATALENGTH(@ReplaceNewlineWith)/2)
			END

			RETURN @Result
		END
		')

		Exec (@SQL)

		SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''; SET @SQL4=''	
		Set @SQL=Concat('
		Create or Alter Proc dbo.ProcStarter
			@TargetObjectID			as bigint,
			@Ladeverfahren			as nvarchar(2)	--> Wenn ''F'' dann Fulload für alle geänderten Tabellen, wenn ''D'' dann Deltaload, wenn ''FN'' Fulload für alle Tabellen. Sonst entscheidet das Skript automatische über das Ladeverfahren anhand der Einstellungen
		as
		Begin
			DECLARE @SQL as nvarchar(max)
			DECLARE @SQL1 as nvarchar(max)
			DECLARE @SQL2 as nvarchar(max)
			DECLARE @SQL3 as nvarchar(max)
			DECLARE @SQL4 as nvarchar(max)
			DECLARE @SQL5 as nvarchar(max)
			DECLARE @SQL6 as nvarchar(max)
			DECLARE @SQL7 as nvarchar(max)
			DECLARE @SQL8 as nvarchar(max)
			DECLARE @SQL9 as nvarchar(max)
			DECLARE @SQL10 as nvarchar(max)
			DECLARE @SQL11 as nvarchar(max)
	
			Select @SQL10=case when LEN(@Ladeverfahren)>0 then Replace(Konfig,substring(Konfig, Charindex(''@Ladeverfahren'',Konfig), Charindex('','',Konfig,Charindex(''@Ladeverfahren'',Konfig))-Charindex(''@Ladeverfahren'',Konfig)),''@Ladeverfahren=''''''+@Ladeverfahren+'''''''') else Konfig end
			FROM ',@SQL_TableRelationTreeString,' where [TargetObjectID]=@TargetObjectID

			if @SQL10 is not null
				begin

					Set @SQL=substring(cast(@SQL10 as ntext),1,4000) 
					Set @SQL1=substring(cast(@SQL10 as ntext),4001,8000) 
					Set @SQL2=substring(cast(@SQL10 as ntext),8001,12000) 
					Set @SQL3=substring(cast(@SQL10 as ntext),12001,16000) 
					Set @SQL4=substring(cast(@SQL10 as ntext),16001,20000) 
					Set @SQL5=substring(cast(@SQL10 as ntext),20001,24000) 
					Set @SQL6=substring(cast(@SQL10 as ntext),24001,28000) 
					Set @SQL7=substring(cast(@SQL10 as ntext),28001,32000) 
					Set @SQL8=substring(cast(@SQL10 as ntext),32001,36000) 
					Set @SQL9=substring(cast(@SQL10 as ntext),36001,40000) 
					Set @SQL10=substring(cast(@SQL10 as ntext),40001,44000) 

					print (@SQL)
					print (@SQL1)
					print (@SQL2)
					print (@SQL3)
					print (@SQL4)
					print (@SQL5)
					print (@SQL6)
					print (@SQL7)
					print (@SQL8)
					print (@SQL9)
					print (@SQL10)

					exec (@SQL+@SQL1+@SQL2+@SQL3+@SQL4+@SQL5+@SQL6+@SQL7+@SQL8+@SQL9+@SQL10)
				end
			else
				begin
					Print ''Fehler!!! Keine Tabelle mit der ObjektID=''+cast(@TargetObjectID as varchar(50))+'' gefunden!!!''
				end

		end
		')

		Exec (@SQL)

		Return (@Datenweg)
	end

