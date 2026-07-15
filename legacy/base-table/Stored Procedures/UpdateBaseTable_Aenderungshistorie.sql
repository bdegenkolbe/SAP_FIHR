USE [Analysen]
GO

CREATE or ALTER PROC [dbo].[UpdateBaseTable_Aenderungshistorie]
	@DELAY int						=2,		--> Greift im Delta-Modus die Daten n-Tage (00:00:00 Uhr) vor dem letzten Ladevorgang ab. 
	@MaxDelay	as int				=0,		--> Maximale Verzögerung des letzten Aktualisierung einer Quelltabelle in Minuten. Insofern 0 oder negative Zahlen verwendet werden, bezieht sich die Verzögerung auf Tage. (0 die Aktualisierung muss von heute sein, -1 die Aktualisierung muss von gestern sein)
	@DeltaDays as int				=2,		--> Delta-Load beinhaltet alle Datenzeilen für geänderte IDs der letzten n-Tage (00:00:00 Uhr)
	@DaysToFullLoad int				=7,		--> Aller wieviel Tage soll ein Fullload automatisch durchgeführt werden?
	@TestLoop nvarchar(100)			='',	--> bspw. 'Top 100' für 100 Testdatensätze
	@FullloadYears as int			=5,		--> Jahre die als Fullload geladen werden sollen, 0=Delta-Load
	@Ladeverfahren as nvarchar(2)	='',	--> Wenn 'F' dann Fulload, wenn 'D' dann Deltaload aus der Original-Tabelle; Sonst entscheidet das Skript automatische über das Ladeverfahren anhand der Einstellungen
	@CDPOS_laden as int				=0,		--> Wenn 1 wird die CDPOS bei Änderungen geladen, wenn 2 wird CDPOS immer geladen, wenn 0 wird CDPOS nicht geladen, wenn 2 wird die CDPOS immer geladen!!!
	@LastChangeFromTarget as int	=0,		--> Wenn 1 wird der letzte Änderungszeitpunkt aus der TargetTabelle berechnet - langsam/0=Änderungszeitpunkt wird aus den SYS-Tabellen berechnet
	@HashAbgleich_ct as int			=0,		--> 1=Nur relevanten Änderungen in den ct Tabellen werden mit einem HASH über die ausgewählten Spalten verarbeitet/0=keine Hash-Prüfung im ersten Schritt
	@InsertInto as int				=0,		--> 1=[Insert Into Select...], 0=[Select ... into...]. Die Befehle [Insert Into] und [Into] haben unterschiedliche Performance-Eigenschaften. Einfach die schnellste wählen.
	@Historisierung as int			=1,		--> 2=Historisierte Werte aus Quelltabelle; 1=Historisierte Werte aus CT-Tabellen und der CDPOS werden abgefragt / 0=keine historisierten Werte
	@PreProcessing as int			=1,		--> 1=Vorprozesse werden ausgeführt
	@PostProcessing as int			=1,		--> 1=Nachprozesse werden ausgeführt
	@TEMPPraefix as nvarchar(100)	='New',	--> 'New' wird eine neue TempID für alle Temptabellen vergeben (Standard). Hier kann ein beliebiger Wert eingegeben werden, der als Präfix für alle temporären Tabellen verwendet wird.
	@TEMPLoeschen as int			=1,		--> Wenn 1 werden alle Tempdateien gelöscht (Standard).
	@StartStep as varchar(10)		='',	--> Startet mit Prozessschritt bspw. 'XP270'
	@LastChangeOnDate as int		=1,		--> Wenn 1 werden nur die letzten Änderungen eines Tages ausgewertet. Wenn 0 werden alle datensätze ausgewertet.
	@ValidToStorno as int			=1,		--> Wenn 1 wird der Gültigkeitszeitraum des Datensatzes zum Stornozeitpunkt beendet (Standard). Wenn 0 ist der Datensatz auch nach dem Stornozeitpunkt gültig. Änderungen nach dem Stornozeitpunkt werden nicht mehr verarbeitet, unabhängig von LastChangeOnDate.
	@ValidBeforeStorno as int		=1,		--> Wenn 1 sind alle Datensätze eine Zeiteinheit vor einem Storno gültig (Standard). Wenn 0 sind alle Datensätze genau bis zum Storno gültig.

	@AddDeleteAfterLastEntry AS Int	= 1,	--> Fehlendes DELETE x Zeiteinheiten nach letzter Änderung in Historie einfügen. Insofern 0 oder negativ, ist die Angabe in Minuten, positive Einträge werden als Tage behandelt.
	@AddInsertBeforeEntry AS Int	= 1,	--> Fehlendes INSERT x Zeiteinheiten vor betroffener Änderung in Historie einfügen. Insofern 0 oder negativ, ist die Angabe in Minuten, positive Einträge werden als Tage behandelt.
	@AddUpdateBeforeEntry AS Int	= 1,	--> Fehlendes UPDATE x Zeiteinheiten vor betroffener Änderung in Historie einfügen. Insofern 0 oder negativ, ist die Angabe in Minuten, positive Einträge werden als Tage behandelt.
	@AddDeleteBeforeEntry AS Int	= 1,	--> Fehlendes DELETE x Zeiteinheiten vor betroffener Änderung in Historie einfügen. Insofern 0 oder negativ, ist die Angabe in Minuten, positive Einträge werden als Tage behandelt.

	@IgnoreChangesWithinTime AS Int	= -10,	--> Mehrere Änderungen innerhalb von x Zeiteinheiten ignorieren und letzten Zustand behalten. Insofern 0 oder negativ, ist die Angabe in Sekunden, positive Einträge werden als Minuten behandelt.

	@SQL_PreProcessing1 as varchar(max)='',
	@SQL_PreProcessing2 as varchar(max)='',
	@SQL_PreProcessing3 as varchar(max)='',
	@SQL_PreProcessing4 as varchar(max)='',
	@SQL_PreProcessing5 as varchar(max)='',
	@SQL_PostProcessing1 as varchar(max)='',
	@SQL_PostProcessing11 as varchar(max)='',
	@SQL_PostProcessing2 as varchar(max)='',
	@SQL_PostProcessing3 as varchar(max)='',
	@SQL_PostProcessing4 as varchar(max)='',
	@SQL_PostProcessing5 as varchar(max)='',

	@SQL_TableSourceDB as nvarchar(200)='',
	@SQL_TableSourceSchema as nvarchar(200)='',
	@SQL_TableSourceName as nvarchar(200)='',
	@SQL_TableSourceString as nvarchar(200)='',
	@SQL_TableSourceFields as nvarchar(max)='',
	@SQL_TableSourceID as nvarchar(200)='',
	@SQL_TableSourceCreateDate as nvarchar(500)='',
	@SQL_TableSourceUpDate as nvarchar(500)='',
	@SQL_TableSourceStornoDate as nvarchar(500)='',
	@SQL_TableSourceStornoField as nvarchar(500)='',
	@SQL_TableSourceStornoFlag as nvarchar(500)='',

	@SQL_TableSource_Join as nvarchar(max)='',
	@SQL_TableSource_Kopf as nvarchar(max)='',
	@SQL_TableSource_Fuss as nvarchar(max)='',
	@SQL_TableSource_Where as nvarchar(max)='',

	@SQL_TableTargetDB as nvarchar(200)='',
	@SQL_TableTargetSchema as nvarchar(200)='',
	@SQL_TableTargetName as nvarchar(200)='',
	@SQL_TableTargetString as nvarchar(200)='',
	@SQL_TableTargetFields as nvarchar(max)='',
	@SQL_TableTargetID as nvarchar(450)='SchluesselID',
	@SQL_TableTarget_Join as nvarchar(max)='',
	@SQL_TableTarget_Where as nvarchar(max)='',
	@SQL_TableTargetDefinition1 as nvarchar(max)='',
	@SQL_TableTargetDefinition2 as nvarchar(max)='',
	@SQL_TableTargetDefinition3 as nvarchar(max)='',

	@SQL_TableTargetUpDate		as nvarchar(400)='|x|Datensatz_geaendert_am',
	@SQL_TableTargetCreateDate	as nvarchar(400)='|x|Datensatz_erstellt_am',
	@SQL_TableTargetStornoDate	as nvarchar(400)='|x|Datensatz_storniert_am',
	@SQL_TableTargetStornoFlag	as nvarchar(400)='|x|Datensatz_ist_storniert',
	@SQL_TableTargetDeleteDate	as nvarchar(400)='|x|Datensatz_geloescht_am',
	@SQL_TableTargetDeleteFlag	as nvarchar(400)='|x|Datensatz_ist_geloescht',
	@SQL_TableTargetValidFrom	as nvarchar(400)='|x|Datensatz_gueltig_von',
	@SQL_TableTargetValidTo		as nvarchar(400)='|x|Datensatz_gueltig_bis',
	
	@SQL_TableLoggingName		as nvarchar(200)='Admin_Log',
	@SQL_TableLoggingString		as nvarchar(200)='',
	@SQL_TableTabStatusName		as nvarchar(200)='Admin_TabStatus',
	@SQL_TableTabStatusString	as nvarchar(200)='',
	@SQL_TableQlikLoadName		as nvarchar(200)='Admin_QlikLoad',
	@SQL_TableQlikLoadString	as nvarchar(200)='',
	@SQL_TableRelationTreeName	as nvarchar(299)='Admin_TabTree',
	@SQL_TableRelationTreeString		as nvarchar(299)='',

	@CDPOS_TableID as nvarchar(200)=''
as
Begin

	PRINT 'Starte Skripabarbeitung für Prozedur [UpdateBaseTable_Aenderungshistorie]'

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

	DECLARE @SQL_Konfig as nvarchar(max)
	DECLARE @SQL_Konfig1 as nvarchar(max)
	DECLARE @SQL_Konfig2 as nvarchar(max)
	DECLARE @SQL_Konfig3 as nvarchar(max)
	DECLARE @SQL_Konfig4 as nvarchar(max)
	DECLARE @SQL_Konfig5 as nvarchar(max)
	DECLARE @SQL_Konfig6 as nvarchar(max)
	DECLARE @SQL_Konfig7 as nvarchar(max)
	DECLARE @SQL_Konfig8 as nvarchar(max)
	DECLARE @SQL_Konfig9 as nvarchar(max)
	DECLARE @SQL_Konfig10 as nvarchar(max)

	DECLARE @LastLoadLocal DateTime2
	DECLARE @LastLoadUTC DateTime2
	DECLARE @LastProcessedChangeLocal DateTime2
	DECLARE @LastFullLoadLocal DateTime2
	DECLARE @LastFullLoadUTC DateTime2
	DECLARE @TableCTLastUpdateLocal as DateTime2
	DECLARE @TableCTLastUpdateUTC as DateTime2
	DECLARE @TableLastUpdate as DateTime2
	DECLARE @SnapshotTimestampUTC as DateTime2
	DECLARE @Zeit DateTime2
	DECLARE @Start DateTime2
	DECLARE @Datenweg int
	DECLARE @Zaehler as int
	DECLARE @StepPraefix as nvarchar(100)
	DECLARE @Praefix as nvarchar(100)
	DECLARE @PraefixStart as nvarchar(100)
	DECLARE @Fehler as int
	DECLARE @FehlerText as nvarchar(4000)
	DECLARE @Zeilenanzahl as bigint
	DECLARE @RowCount as bigint
	DECLARE @StepText nvarchar(500)
	DECLARE @Konfiguration as nvarchar(max)

	DECLARE @Fieldlist1 as varchar(max)
	DECLARE @Fieldlist2 as varchar(max)
	DECLARE @FieldList3 as varchar(max)
	DECLARE @FieldList4 as varchar(max)
	DECLARE @FieldList5 as varchar(max)
	DECLARE @Fieldlist6 as varchar(max)

	DECLARE @CDPOS_Original_Zeilenanzahl_Neu bigint
	DECLARE @CDPOS_Original_Zeilenanzahl_Alt bigint
	DECLARE @CDPOS_Zeilenanzahl_Neu as bigint
	DECLARE @CDPOS_Zeilenanzahl_Alt as bigint
	DECLARE @CDPOS_Zeilenanzahl_Auswahl bigint

	DECLARE @LogID bigint
	DECLARE @CountDate as Date
	DECLARE @MaxDelayTimestamp as DateTime2

	SET @Zeit=Getdate();
	SET @Start=@Zeit;
	SET @FehlerText=''
	SET @Fehler=0

	If @MaxDelay<1
		SET @MaxDelayTimestamp=cast(Dateadd(DAY,@MaxDelay,cast(getdate() as date)) as DateTime2)
	else
		SET @MaxDelayTimestamp=Dateadd(MINUTE,-@MaxDelay,getdate())
	
	Print @MaxDelay

	if CHARINDEX('|x|',@SQL_TableTargetID)=0
		Set @SQL_TableTargetID=CONCAT('|x|',@SQL_TableTargetID)

	If @TEMPPraefix='New' 
		Select @TEMPPraefix=cast(rand()*cast(Getdate() as int)*10000 as int)

	if len(@TestLoop)>0
		Begin
			Set @SQL_TableTargetString= concat(@SQL_TableTargetString,'_TEST')
			Set @SQL_TableTargetName=	concat(@SQL_TableTargetName,'_TEST')
		End

	If LEN(Trim(@SQL_TableSourceString))=0 or @SQL_TableSourceString is null
		SET @SQL_TableSourceString=		concat(@SQL_TableSourceDB,'.',@SQL_TableSourceSchema,'.',@SQL_TableSourceName)

	SET @SQL_TableSourceString = replace(replace(@SQL_TableSourceString,'[',''),']','')

	If LEN(Trim(@SQL_TableTargetString))=0 or @SQL_TableTargetString is null
		SET @SQL_TableTargetString=		concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableTargetName)

	SET @SQL_TableTargetString = replace(replace(@SQL_TableTargetString,'[',''),']','')

	If LEN(Trim(@SQL_TableLoggingString))=0 or @SQL_TableLoggingString is null
		SET @SQL_TableLoggingString=	concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableLoggingName)

	If LEN(Trim(@SQL_TableTabStatusString))=0 or @SQL_TableTabStatusString is null
		SET @SQL_TableTabStatusString=	concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableTabStatusName)

	If LEN(Trim(@SQL_TableQlikLoadString))=0 or @SQL_TableQlikLoadString is null
		SET @SQL_TableQlikLoadString=	concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableQlikLoadName)

	If LEN(Trim(@SQL_TableRelationTreeString))=0 or @SQL_TableRelationTreeString is null
		SET @SQL_TableRelationTreeString=	concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableRelationTreeName)

	If @FullloadYears <0 or @FullloadYears>20 or @FullloadYears is Null
		Set @FullloadYears=5
		
	SET @SQL_Konfig=''; SET @SQL_Konfig1=''; SET @SQL_Konfig2=''; SET @SQL_Konfig3=''; SET @SQL_Konfig4=''; SET @SQL_Konfig5=''; SET @SQL_Konfig6=''; SET @SQL_Konfig7=''; SET @SQL_Konfig8=''; SET @SQL_Konfig9=''; SET @SQL_Konfig10=''

	Set @SQL_Konfig=concat('
		@DELAY 					=',replace(@DELAY,'''',''''''''''),', 
		@MaxDelay				=',replace(@MaxDelay,'''',''''''''''),', 
		@DeltaDays 				=',replace(@DeltaDays,'''',''''''''''),', 
		@DaysToFullLoad 		=',replace(@DaysToFullLoad,'''',''''''''''),', 
		@TestLoop 				=''''',replace(@TestLoop,'''',''''''''''),''''',
		@FullloadYears 			=',replace(@FullloadYears,'''',''''''''''),', 
		@Ladeverfahren 			=''''',replace(@Ladeverfahren,'''',''''''''''),''''',
		@CDPOS_laden 			=',replace(@CDPOS_laden,'''',''''''''''),', 
		@LastChangeFromTarget 	=',replace(@LastChangeFromTarget,'''',''''''''''),', 
		@HashAbgleich_ct 		=',replace(@HashAbgleich_ct,'''',''''''''''),', 
		@InsertInto 			=',replace(@InsertInto,'''',''''''''''),', 
		@Historisierung 		=',replace(@Historisierung,'''',''''''''''),', 
		@PreProcessing 			=',replace(@PreProcessing,'''',''''''''''),', 
		@PostProcessing 		=',replace(@PostProcessing,'''',''''''''''),', 
		@TEMPPraefix 			=''''',replace(@TEMPPraefix,'''',''''''''''),''''',
		@TEMPLoeschen 			=',replace(@TEMPLoeschen,'''',''''''''''),', 
		@StartStep 				=''''',replace(@StartStep,'''',''''''''''),''''',
		@LastChangeOnDate 		=',replace(@LastChangeOnDate,'''',''''''''''),', 
		@ValidToStorno 			=',replace(@ValidToStorno,'''',''''''''''),', 
		@ValidBeforeStorno 		=',replace(@ValidBeforeStorno,'''',''''''''''),', 
		')
	Set @SQL_Konfig1=concat('
		@SQL_PreProcessing1 	=''''',replace(@SQL_PreProcessing1,'''',''''''''''),''''',
		@SQL_PreProcessing2		=''''',replace(@SQL_PreProcessing2,'''',''''''''''),''''',
		@SQL_PreProcessing3 	=''''',replace(@SQL_PreProcessing3,'''',''''''''''),''''',
		')
	Set @SQL_Konfig2=concat('
		@SQL_PreProcessing4 	=''''',replace(@SQL_PreProcessing4,'''',''''''''''),''''',
		@SQL_PreProcessing5 	=''''',replace(@SQL_PreProcessing5,'''',''''''''''),''''',
		@SQL_PostProcessing1 	=''''',replace(@SQL_PostProcessing1,'''',''''''''''),''''',
		')

	Set @SQL_Konfig3=concat('
		@SQL_PostProcessing11 	=''''',replace(@SQL_PostProcessing11,'''',''''''''''),''''',
		@SQL_PostProcessing2	=''''',replace(@SQL_PostProcessing2,'''',''''''''''),''''',
		@SQL_PostProcessing3 	=''''',replace(@SQL_PostProcessing3,'''',''''''''''),''''',
		')
	Set @SQL_Konfig4=concat('
		@SQL_PostProcessing4 	=''''',replace(@SQL_PostProcessing4,'''',''''''''''),''''',
		@SQL_PostProcessing5 	=''''',replace(@SQL_PostProcessing5,'''',''''''''''),''''',
		')
	Set @SQL_Konfig5=concat('
		@SQL_TableSourceDB 			=''''',replace(@SQL_TableSourceDB,'''',''''''''''),''''',
		@SQL_TableSourceSchema 		=''''',replace(@SQL_TableSourceSchema,'''',''''''''''),''''',
		@SQL_TableSourceName 		=''''',replace(@SQL_TableSourceName,'''',''''''''''),''''',
		@SQL_TableSourceString 		=''''',replace(@SQL_TableSourceString,'''',''''''''''),''''',
		@SQL_TableSourceFields 		=''''',replace(@SQL_TableSourceFields,'''',''''''''''),''''',
		@SQL_TableSourceID 			=''''',replace(@SQL_TableSourceID,'''',''''''''''),''''',
		@SQL_TableSourceCreateDate 	=''''',replace(@SQL_TableSourceCreateDate,'''',''''''''''),''''',
		@SQL_TableSourceUpDate 		=''''',replace(@SQL_TableSourceUpDate,'''',''''''''''),''''',
		@SQL_TableSourceStornoDate 	=''''',replace(@SQL_TableSourceStornoDate,'''',''''''''''),''''',
		@SQL_TableSourceStornoField =''''',replace(@SQL_TableSourceStornoField,'''',''''''''''),''''',
		@SQL_TableSourceStornoFlag 	=''''',replace(@SQL_TableSourceStornoFlag,'''',''''''''''),''''',
		')
	Set @SQL_Konfig6=concat('
		@SQL_TableSource_Join 	=''''',replace(@SQL_TableSource_Join,'''',''''''''''),''''',
		@SQL_TableSource_Kopf 	=''''',replace(@SQL_TableSource_Kopf,'''',''''''''''),''''',
		@SQL_TableSource_Fuss 	=''''',replace(@SQL_TableSource_Fuss,'''',''''''''''),''''',
		@SQL_TableSource_Where 	=''''',replace(@SQL_TableSource_Where,'''',''''''''''),''''',

		@SQL_TableTargetDB 		=''''',replace(@SQL_TableTargetDB,'''',''''''''''),''''',
		@SQL_TableTargetSchema 	=''''',replace(@SQL_TableTargetSchema,'''',''''''''''),''''',
		@SQL_TableTargetName 	=''''',replace(@SQL_TableTargetName,'''',''''''''''),''''',
		@SQL_TableTargetString 	=''''',replace(@SQL_TableTargetString,'''',''''''''''),''''',
		@SQL_TableTargetFields 	=''''',replace(@SQL_TableTargetFields,'''',''''''''''),''''',
		@SQL_TableTargetID 		=''''',replace(@SQL_TableTargetID,'''',''''''''''),''''',
		@SQL_TableTarget_Join 	=''''',replace(@SQL_TableTarget_Join,'''',''''''''''),''''',
		@SQL_TableTarget_Where 	=''''',replace(@SQL_TableTarget_Where,'''',''''''''''),''''',
		')
	Set @SQL_Konfig7=concat('
		@SQL_TableTargetDefinition1 	=''''',replace(@SQL_TableTargetDefinition1,'''',''''''''''),''''',
		')
	Set @SQL_Konfig8=concat('	
		@SQL_TableTargetDefinition2 	=''''',replace(@SQL_TableTargetDefinition2,'''',''''''''''),''''',
		')
	Set @SQL_Konfig9=concat('
		@SQL_TableTargetDefinition3 	=''''',replace(@SQL_TableTargetDefinition3,'''',''''''''''),''''',
		')
	Set @SQL_Konfig10=concat('
		@SQL_TableTargetUpDate 		=''''',replace(@SQL_TableTargetUpDate,'''',''''''''''),''''',
		@SQL_TableTargetCreateDate 	=''''',replace(@SQL_TableTargetCreateDate,'''',''''''''''),''''',
		@SQL_TableTargetStornoDate 	=''''',replace(@SQL_TableTargetStornoDate,'''',''''''''''),''''',
		@SQL_TableTargetStornoFlag 	=''''',replace(@SQL_TableTargetStornoFlag,'''',''''''''''),''''',
		@SQL_TableTargetDeleteDate 	=''''',replace(@SQL_TableTargetDeleteDate,'''',''''''''''),''''',
		@SQL_TableTargetDeleteFlag 	=''''',replace(@SQL_TableTargetDeleteFlag,'''',''''''''''),''''',
		@SQL_TableTargetValidFrom 	=''''',replace(@SQL_TableTargetValidFrom,'''',''''''''''),''''',
		@SQL_TableTargetValidTo 	=''''',replace(@SQL_TableTargetValidTo,'''',''''''''''),''''',
	
		@SQL_TableLoggingName 		=''''',replace(@SQL_TableLoggingName,'''',''''''''''),''''',
		@SQL_TableLoggingString 	=''''',replace(@SQL_TableLoggingString,'''',''''''''''),''''',
		@SQL_TableTabStatusName 	=''''',replace(@SQL_TableTabStatusName,'''',''''''''''),''''',
		@SQL_TableTabStatusString 	=''''',replace(@SQL_TableTabStatusString,'''',''''''''''),''''',
		@SQL_TableQlikLoadName 		=''''',replace(@SQL_TableQlikLoadName,'''',''''''''''),''''',
		@SQL_TableQlikLoadString 	=''''',replace(@SQL_TableQlikLoadString,'''',''''''''''),''''',
		@SQL_TableRelationTreeName 	=''''',replace(@SQL_TableRelationTreeName,'''',''''''''''),''''',
		@SQL_TableRelationTreeString=''''',replace(@SQL_TableRelationTreeString,'''',''''''''''),''''',

		@CDPOS_TableID =''''',replace(@CDPOS_TableID,'''',''''''''''),'''''
		')

	If LEN(TRIM(@SQL_TableTargetUpDate))	=0  or @SQL_TableTargetUpDate is null
		Set @SQL_TableTargetUpDate			='|x|Datensatz_geaendert_am'
	If LEN(TRIM(@SQL_TableTargetCreateDate))=0  or @SQL_TableTargetCreateDate is null
		Set @SQL_TableTargetCreateDate		='|x|Datensatz_erstellt_am'
	If LEN(TRIM(@SQL_TableTargetStornoDate))=0  or @SQL_TableTargetStornoDate is null
		Set @SQL_TableTargetStornoDate		='|x|Datensatz_storniert_am'
	If LEN(TRIM(@SQL_TableTargetStornoFlag))=0  or @SQL_TableTargetStornoFlag is null
		Set @SQL_TableTargetStornoFlag		='|x|Datensatz_ist_storniert'
	If LEN(TRIM(@SQL_TableTargetDeleteDate))=0  or @SQL_TableTargetDeleteDate is null
		Set @SQL_TableTargetDeleteDate		='|x|Datensatz_geloescht_am'
	If LEN(TRIM(@SQL_TableTargetDeleteFlag))=0  or @SQL_TableTargetDeleteFlag is null
		Set @SQL_TableTargetDeleteFlag		='|x|Datensatz_ist_geloescht'
	If LEN(TRIM(@SQL_TableTargetValidFrom))	=0  or @SQL_TableTargetValidFrom is null
		Set @SQL_TableTargetValidFrom		='|x|Datensatz_gueltig_von'
	If LEN(TRIM(@SQL_TableTargetValidTo))	=0  or @SQL_TableTargetValidTo is null
		Set @SQL_TableTargetValidTo			='|x|Datensatz_gueltig_bis'	

	if left(trim(replace(replace(@SQL_TableTargetDefinition1,CHAR(10),''),CHAR(13),'')),1)<>','  and LEN(@SQL_TableTargetDefinition1)>5
		Set @SQL_TableTargetDefinition1=','+@SQL_TableTargetDefinition1
	else 
		Set @SQL_TableTargetDefinition1=''

	SET @SQL_TableSourceFields		= Replace(@SQL_TableSourceFields,'|x|','')
	SET @SQL_TableSourceFields		= (Select dbo.CleanAndTrim(@SQL_TableSourceFields,'','',0))

	IF @SQL_TableSourceCreateDate = ''
		SET @SQL_TableSourceCreateDate	= 'DateTime2FromParts(2099,01,01,12,00,00,00,7)'
	IF @SQL_TableSourceUpDate = ''
		SET @SQL_TableSourceUpDate		= 'DateTime2FromParts(1900,01,01,12,00,00,00,7)'
	IF @SQL_TableSourceStornoDate = ''
		SET @SQL_TableSourceStornoDate	= 'DateTime2FromParts(2099,01,01,12,00,00,00,7)'

	SET @SQL=Concat('Use ',@SQL_TableTargetDB);
	EXEC(@SQL);
 
	Print 'Konfiguration der Laufzeitumgebung'
	Print '@SQL_TableTargetDB= '+ @SQL_TableTargetDB
	Print '@SQL_TableTargetSchema= '+ @SQL_TableTargetSchema
	Print '@SQL_TableLoggingString= '+ @SQL_TableLoggingString
	Print '@SQL_TableTabStatusString= '+ @SQL_TableTabStatusString
	Print '@SQL_TableQlikLoadString= '+ @SQL_TableQlikLoadString
	Print '@SQL_TableRelationTreeString= '+ @SQL_TableRelationTreeString

	Execute dbo.Konfiguration @SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,  @SQL_TableLoggingString=@SQL_TableLoggingString, @SQL_TableTabStatusString=@SQL_TableTabStatusString, @SQL_TableQlikLoadString=@SQL_TableQlikLoadString, @SQL_TableRelationTreeString=@SQL_TableRelationTreeString,@Datenweg=@Datenweg OUTPUT; 
	Print '------------------------------------------'

	IF OBJECT_ID(@SQL_TableTargetString, 'U') IS NULL 
		Begin 
			SET @Datenweg=1
			PRINT 'Notwendige Daten für den FastTrack sind weg!'
		End
	else
		Begin
			SET @Datenweg=0
		end 

	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

	Print 'Start Logging'

    -- Erstellt eine temporäre Prozedur, die die Standardparameter automatisch setzt
    SET @SQL = CONCAT('
        CREATE PROCEDURE #LogStep
            @LogID                  AS BigInt           = NULL OUTPUT,
            @LogTableName           AS nVarChar(200)    = '''',
            @LogTableTime           AS DateTime2         = NULL,
            @LogTableProcess        AS nVarChar(200)    = '''',
            @LogTableProcessMode    AS nVarChar(50)     = '''',
            @LogTableProcessStatus  AS nVarChar(20)     = ''PROCESS'',
            @LogStep                AS nVarChar(20)     = '''',
            @LogStepText            AS nVarChar(500)    = '''',
            @LogStepStart           AS DateTime2         = NULL,
            @LogStepEnd             AS DateTime2         = NULL,
            @LogStepSQL             AS VarChar(max)     = '''',
            @LogStepSQL1            AS VarChar(max)     = '''',
            @LogStepSQL2            AS VarChar(max)     = '''',
            @LogStepSQL3            AS VarChar(max)     = '''',
            @LogStepSQL4            AS VarChar(max)     = '''',
            @LogStepSQL5            AS VarChar(max)     = '''',
            @LogStepSQL6            AS VarChar(max)     = '''',
            @LogStepSQL7            AS VarChar(max)     = '''',
            @LogStepSQL8            AS VarChar(max)     = '''',
            @LogStepSQL9            AS VarChar(max)     = '''',
            @LogStepSQL10           AS VarChar(max)     = '''',
            @LogStepRows            AS BigInt           = 0,
            @LogStepStatus          AS nVarChar(200)    = ''FINISHED'',
            @LogStepError           AS Int              = NULL,
            @LogStepErrorText       AS nVarChar(4000)   = '''',
            @LogTime                AS DateTime2         = NULL,
            @LogUser                AS nVarChar(100)    = NULL
	    AS
            BEGIN
                -- eigentliche Logging-Prozedur aufrufen
                EXEC dbo.Logging
                    -- Feste Parameter, die der Wrapper automatisch setzt
                    @SQL_TableLoggingString      = ''', @SQL_TableLoggingString, ''',
                    @SQL_TableRelationTreeString = ''', @SQL_TableRelationTreeString, ''',

                    -- Parameter, die vom Aufruf durchgereicht werden
                    @LogID                  = @LogID OUTPUT,
                    @LogTableName           = @LogTableName,
                    @LogTableTime           = @LogTableTime,
                    @LogTableProcess        = @LogTableProcess,
                    @LogTableProcessMode    = @LogTableProcessMode,
                    @LogTableProcessStatus  = @LogTableProcessStatus,
                    @LogStep                = @LogStep,
                    @LogStepText            = @LogStepText,
                    @LogStepStart           = @LogStepStart,
                    @LogStepEnd             = @LogStepEnd,
                    @LogStepSQL             = @LogStepSQL,
                    @LogStepSQL1            = @LogStepSQL1,
                    @LogStepSQL2            = @LogStepSQL2,
                    @LogStepSQL3            = @LogStepSQL3,
                    @LogStepSQL4            = @LogStepSQL4,
                    @LogStepSQL5            = @LogStepSQL5,
                    @LogStepSQL6            = @LogStepSQL6,
                    @LogStepSQL7            = @LogStepSQL7,
                    @LogStepSQL8            = @LogStepSQL8,
                    @LogStepSQL9            = @LogStepSQL9,
                    @LogStepSQL10           = @LogStepSQL10,
                    @LogStepRows            = @LogStepRows,
                    @LogStepStatus          = @LogStepStatus,
                    @LogStepError           = @LogStepError,
                    @LogStepErrorText       = @LogStepErrorText,
                    @LogTime                = @LogTime,
                    @LogUser                = @LogUser;
            END
	');
    IF OBJECT_ID('tempdb..#LogStep') IS NOT NULL
        DROP PROCEDURE #LogStep;
    EXEC(@SQL);

    Set @SQL= concat('
					Delay				:',@DELAY,'
					MaxDelay			:',@MaxDelay,'
					MaxDelayTimestamp	:',@MaxDelayTimestamp,'
					Zyklus				:',@DaysToFullLoad,'
					TestDurchLauf		:',@TestLoop,'
					Delta				:',@DeltaDays,'
					Fullload			:',@FullloadYears,'
					Ladeverfahren		:',@Ladeverfahren,'
					CDPOS_laden			:',@CDPOS_laden,'
					LastChangeFromTarget:',@LastChangeFromTarget,'
					HashAbgleich_ct		:',@HashAbgleich_ct,'
					Historisierung		:',@Historisierung,'
					PreProcessing		:',@PreProcessing,'
					PostProcessing		:',@PostProcessing,'
					TEMPPraefix			:',@TEMPPraefix,'
					TEMPLoeschen		:',@TEMPLoeschen,'
					StartStep			:',@StartStep,'
					gueltig_von			:',Replace(@SQL_TableTargetValidFrom,'|x|',''),'
					gueltig_bis			:',Replace(@SQL_TableTargetValidTo,'|x|',''),'
					Source Tabelle		:',@SQL_TableSourceString,'
					Target Tabelle		:',@SQL_TableTargetString,'
					Logging Tabelle		:',@SQL_TableLoggingString,'
					Status Tabelle		:',@SQL_TableTabStatusString,'
					QlikLoad Tabelle	:',@SQL_TableQlikLoadString,'
					TargetString		:',@SQL_TableLoggingString,'
					LastChangeOnDate	:',@LastChangeOnDate,'
					ValidAfterStorno	:',@ValidBeforeStorno,'
					ValidToStorno		:',@ValidToStorno,'
					')

	Execute #LogStep @LogID=@LogID Output,
						@LogTableName=@SQL_TableTargetString,
						@LogTableProcess='UpdateBaseTable_Aenderungshistorie',
						@LogTableProcessMode='INIT',
						@LogTableProcessStatus='START',
						@LogStep='START',
						@LogStepText='START',
						@LogStepStart=@Start,
						@LogStepSQL=@SQL,
						@LogStepRows=0,
						@LogStepStatus='START'

	if @Fehler>0
		goto Fehlermarke

	IF OBJECT_ID(@SQL_TableSourceString, 'U') IS NULL 
		Begin
			Set @Fehler=99991 
			Set @FehlerText= concat('Quelltabelle [',@SQL_TableSourceString,'] fehlt!')
			Print concat('Fehler!!!!: ',@Fehler)
			Print @FehlerText
			goto Fehlermarke
		End	

	SET @StepText=Concat('Abrufen des letzten Änderung in der Quelltabelle [',@SQL_TableSourceString,'].')
	SET @SQL=Concat('SELECT @TableLastUpdate = (Select max(isnull(t2.last_user_update,t1.modify_date)) as Datum
							  from ',@SQL_TableSourceDB,'.sys.tables t1
							  left join ',@SQL_TableSourceDB,'.SYS.DM_DB_INDEX_USAGE_STATS t2 on t1.object_id=t2.object_id --verwendet Indexdatum, da modify in der sys.table nur strukturänderungen loggt
							  where t1.object_id=',Object_id(@SQL_TableSourceString,'U'),')') --UTC Zeit

	EXEC sp_EXECutesql @SQL, N'@TableLastUpdate DateTime2 OUT', @TableLastUpdate OUT;
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT

	EXEC #LogStep @LogID=@LogID, @LogStep='P10', @LogTableProcessMode='PREPARING',@LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler, @LogTableTime=@TableLastUpdate
			
	if @Fehler>0
		goto Fehlermarke

	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

	IF OBJECT_ID(@SQL_TableLoggingString, 'U') IS NULL 
		Begin
			Set @Fehler=99992
			Set @FehlerText= concat('Logging-Tabelle [',@SQL_TableLoggingString,'] fehlt!')
			Print concat('Fehler!!!!: ',@Fehler)
			Print @FehlerText
			goto Fehlermarke
		End	

-- P20

	SET @StepPraefix = 'P20'
	SET @StepText = CONCAT('Zeitpunkt des letzten Ladeprozesses und der letzten verarbeiteten Änderung in Zieltabelle [', @SQL_TableTargetString, '] aus Beziehungs-Tabelle [', @SQL_TableRelationTreeString, '] abrufen.')

	SET @SQL =	CONCAT('SELECT 
							@LastLoadLocal = MAX(TargetUpdate)
						,	@LastProcessedChangeLocal =	MAX(SourceUpdate)
						FROM ', @SQL_TableRelationTreeString, '
						WHERE CONCAT(TargetTableDB, ''.'', TargetTableSchema, ''.'', TargetTableName) = ''', @SQL_TableTargetString, ''''
				)

	EXEC sp_EXECutesql @SQL, N'@LastLoadLocal AS DateTime2 OUT, @LastProcessedChangeLocal AS DateTime2 OUT', @LastLoadLocal = @LastLoadLocal OUT, @LastProcessedChangeLocal = @LastProcessedChangeLocal OUT;
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT

	EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepRows = @RowCount, @LogStepError = @Fehler

	IF @Fehler > 0
		GoTo Fehlermarke

	SET @SQL=''

	IF  (isnull(@LastLoadLocal,cast('1.1.1990' as DateTime2)) >@TableLastUpdate or isnull(@LastLoadLocal,cast('1.1.1990' as DateTime2)) > @MaxDelayTimestamp) and @Ladeverfahren<>'FN'
		Begin
			Set @Fehler=99993
			Set @FehlerText= concat('Keine Änderungen in der Quelldatei [',@SQL_TableSourceString,'] erkannt.
			@LastLoadLocal=		', convert(nvarchar, @LastLoadLocal, 113),'
			@TableLastUpdate=	', convert(nvarchar, @TableLastUpdate, 113) ,'
			@MaxDelayTimestamp=	', convert(nvarchar, @MaxDelayTimestamp, 113), '
			@Ladeverfahren=		', @Ladeverfahren)
			Print concat('Abbruch!!!!: ',@Fehler)
			Print @FehlerText
			goto Fehlermarke
		End	

	IF @Historisierung=1 and OBJECT_ID(Concat(@SQL_TableSourceString, '__ct'), 'U') IS NULL 
		Begin
			Set @Fehler=99994
			Set @FehlerText= concat('Die Änderungsquelle [',@SQL_TableSourceString,'] fehlt! Historisierung nicht möglich!')
			Print concat('Fehler!!!!: ',@Fehler)
			Print @FehlerText
			goto Fehlermarke
		End	

	IF @Historisierung=1 and OBJECT_ID(Concat(@SQL_TableSourceString, '__ct'), 'U') IS NOT NULL 
		Begin
			SET @StepText=Concat('Abrufen des letzten Änderung in der ct_Tabelle [',@SQL_TableSourceString,'__ct].')
			SET @SQL=Concat('SELECT @TableCTLastUpdateUTC = cast((Select max([header__timestamp]) as Letzte_Aenderung from ',@SQL_TableSourceString,'__ct)  as DateTime2) ') --UTC Zeit

			EXEC sp_EXECutesql @SQL, N'@TableCTLastUpdateUTC DateTime2 OUT', @TableCTLastUpdateUTC OUT;
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT

			If @TableCTLastUpdateUTC is null
				SET @TableCTLastUpdateUTC=CAST(@TableLastUpdate AT TIME ZONE 'Central European Standard Time' AT TIME ZONE 'UTC' as DateTime2 )

			SET @TableCTLastUpdateLocal=CAST(@TableCTLastUpdateUTC AT TIME ZONE 'UTC' AT TIME ZONE 'Central European Standard Time' as DateTime2 )

			EXEC #LogStep @LogID=@LogID, @LogStep='P30', @LogTableProcessMode='PREPARING',@LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler, @LogTableTime=@TableCTLastUpdateLocal
			
			if @Fehler>0
				goto Fehlermarke

			SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
		end

	If @Historisierung=1 and @TableCTLastUpdateUTC is null and OBJECT_ID(Concat(@SQL_TableSourceString, '__ct__bak'), 'U') IS NOT NULL 
		Begin
			SET @StepText=Concat('Abrufen des letzten Änderung in der ct_Tabelle [',@SQL_TableSourceString,'__ct__bak].')
			SET @SQL=Concat('SELECT @TableCTLastUpdateUTC = cast((Select max([header__timestamp]) as Letzte_Aenderung from ',@SQL_TableSourceString,'__ct__bak)  as DateTime2) ') --UTC Zeit

			EXEC sp_EXECutesql @SQL, N'@TableCTLastUpdateUTC DateTime2 OUT', @TableCTLastUpdateUTC OUT;
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT

			If @TableCTLastUpdateUTC is null
				SET @TableCTLastUpdateUTC=CAST(@TableLastUpdate AT TIME ZONE 'Central European Standard Time' AT TIME ZONE 'UTC' as DateTime2 )

			SET @TableCTLastUpdateLocal=CAST(@TableCTLastUpdateUTC AT TIME ZONE 'UTC' AT TIME ZONE 'Central European Standard Time' as DateTime2 )

			EXEC #LogStep @LogID=@LogID, @LogStep='P40', @LogTableProcessMode='PREPARING',@LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler, @LogTableTime=@TableCTLastUpdateLocal
			
			if @Fehler>0
				goto Fehlermarke

			SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
		end
	
	If @Historisierung<>1 or @TableCTLastUpdateUTC is null
		Begin
			SET @TableCTLastUpdateLocal=@TableLastUpdate
			SET @TableCTLastUpdateUTC=CAST(@TableCTLastUpdateLocal AT TIME ZONE 'Central European Standard Time' AT TIME ZONE 'UTC' as DateTime2 )
		end

	SET @StepText=Concat('Abrufen des letzten Full-Loads für die Target-Tabelle [',@SQL_TableTargetString,'] aus der Log-Tabelle [', @SQL_TableLoggingString,'].')
	SET @SQL=Concat('SELECT @LastFullLoadLocal = (Select max(LogTableTime) as Zeitstempel 
								from ',@SQL_TableLoggingString,'
								where LogTableName=''', @SQL_TableTargetString, ''' and upper(LogTableProcessMode) in (''FULL'',''F'',''FN'') and upper(LogTableProcessStatus)=''FINISHED'');')

	EXEC sp_EXECutesql @SQL, N'@LastFullLoadLocal DateTime2 OUT', @LastFullLoadLocal OUT;
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep='P50', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

	if @Fehler>0
		goto Fehlermarke

	IF @LastFullLoadLocal=@TableLastUpdate
		Begin
			Set @Fehler=99995
			Set @FehlerText= concat('Letzter Full-Load entspricht dem Änderungsdatum der Tabelle [',@SQL_TableSourceString,'] !')
			Print concat('Abbruch!!!!: ',@Fehler)
			Print @FehlerText
			goto Fehlermarke
		End	

	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

	IF OBJECT_ID(@SQL_TableTargetString, 'U') IS NOT NULL and (@LastChangeFromTarget=1 or @LastLoadLocal is null)
		Begin
			SET @StepText=Concat('Wenn @LastChangeFromTarget=1 dann wird der letzte Änderungszeitpunkt aus der Target-Tabelle [',@SQL_TableTargetString,'] abgerufen. 
			Insofern sich der Spaltenname für [',Replace(@SQL_TableTargetValidFrom,'|x|',''),'] geändert hat, muss die Target-Tabelle gelöscht oder für @LastChangeFromTarget=0 übermittelt werden.
			Das Laden des letzten Bearbeitungsstandes aus der Target-Tabelle kann in Abhängigkeit der Tabellengröße etwas mehr Zeit in Anspruch nehmen.')

			SET @SQL=Concat('SELECT @LastLoadLocal = (Select max(',Replace(@SQL_TableTargetValidFrom,'|x|',''),') as Letzte_Aenderung from ',@SQL_TableTargetString,')')

			EXEC sp_EXECutesql @SQL, N'@LastLoadLocal DateTime2 OUT', @LastLoadLocal OUT;
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT

			EXEC #LogStep @LogID=@LogID, @LogStep='P60', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler, @LogTableTime=@TableCTLastUpdateLocal

			if @Fehler>0
				goto Fehlermarke

			SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

		End;

	SET @LastLoadUTC=CAST(@LastLoadLocal AT TIME ZONE 'Central European Standard Time' AT TIME ZONE 'UTC' as DateTime2)

	SET @StepText=Concat('','Erstellt die Fieldlist1 mit allen tatsächlich verfügbaren Spalten aus der SourceTable [',@SQL_TableSourceString,']')
	SET @SQL=Concat('SELECT @FieldList1=COALESCE(@FieldList1+N'','', N'''') + ''|x|'' + t1.Spalte
						from (
							SELECT cast(value as nvarchar(50)) as Spalte 
							FROM STRING_SPLIT(''',@SQL_TableSourceFields,''', '','')
							 ) t1
						join (
							SELECT c.name as Spalte, typ.name as Spaltentyp, c.max_length as Spaltenlaenge
							from ',@SQL_TableSourceDB,'.sys.columns c
								join ',@SQL_TableSourceDB,'.sys.tables tab ON c.object_id=tab.object_id
								join ',@SQL_TableSourceDB,'.sys.types typ ON c.user_type_id=typ.user_type_id
							WHERE tab.object_id=',Object_id(@SQL_TableSourceString,'U'),'
							) t2 on t1.Spalte=t2.Spalte
						order by t1.Spalte')

	EXEC sp_EXECutesql @SQL, N'@FieldList1 nvarchar(max) OUT', @Fieldlist1 OUT;

	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep='P70', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

	if @Fehler>0
		goto Fehlermarke

	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

	SET @StepText=Concat('','Erstellt die Fieldlist2 mit allen tatsächlich verfügbaren Spalten aus der SourceTable [',@SQL_TableSourceString,'] und fügt eine TRIM-Funktion hinzu.')
	SET @SQL=Concat('SELECT @FieldList2=COALESCE(@FieldList2+N'','', N'''') + case when CHARINDEX(''char'', t2.Spaltentyp)>0 then ''Trim(|x|'' + t1.Spalte + '')'' else ''|x|'' + t1.Spalte end + '' as '' + t1.Spalte
						from (
							SELECT cast(value as nvarchar(50)) as Spalte 
							FROM STRING_SPLIT(''',@SQL_TableSourceFields,''', '','')
							) t1
						join (
							SELECT c.name as Spalte, typ.name as Spaltentyp, c.max_length as Spaltenlaenge
							from ',@SQL_TableSourceDB,'.sys.columns c
								join ',@SQL_TableSourceDB,'.sys.tables tab ON c.object_id=tab.object_id
								join ',@SQL_TableSourceDB,'.sys.types typ ON c.user_type_id=typ.user_type_id
							WHERE tab.object_id=',Object_id(@SQL_TableSourceString,'U'),'
							) t2 on t1.Spalte=t2.Spalte
						order by t1.Spalte')

	EXEC sp_EXECutesql @SQL, N'@FieldList2 nvarchar(max) OUT', @Fieldlist2 OUT;
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep='P80', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

	if @Fehler>0
		goto Fehlermarke

	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

	SET @StepText=Concat('','Konfiguration der Datenbank')
	SET @SQL=Concat('ALTER DATABASE ',@SQL_TableTargetDB,' SET RECOVERY SIMPLE
					 SET STATISTICS TIME OFF
					 SET NOCOUNT OFF

					 ALTER DATABASE ',@SQL_TableTargetDB,' SET AUTO_CREATE_STATISTICS OFF
					 ALTER DATABASE ',@SQL_TableTargetDB,' SET AUTO_UPDATE_STATISTICS OFF
					 ALTER DATABASE ',@SQL_TableTargetDB,' SET AUTO_UPDATE_STATISTICS_ASYNC OFF')

	EXEC sp_EXECutesql @SQL
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep='P90', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

	if @Fehler>0
		goto Fehlermarke

	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

	If LEN(@StartStep)=0 
		Begin	
			SET @StepText=Concat('','Löschen aller temporären Tabellen [_TEMP',@TEMPPraefix,'%]')
			SET @SQL=Concat('SELECT @SQL1=COALESCE(@SQL1+N''
			'', N'''') + isnull(''Drop Table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.''+ t1.name +'';'','''')
									from ',@SQL_TableTargetDB,'.sys.tables t1
										join ',@SQL_TableTargetDB,'.sys.schemas as t2 on t1.schema_id=t2.schema_id and t2.name=''',@SQL_TableTargetSchema,'''
									where t1.name like ''',@SQL_TableTargetName,'%'' and t1.name like ''%_TEMP',@TEMPPraefix,'%''')

			EXEC sp_EXECutesql @SQL, N'@SQL1 nvarchar(max) OUT', @SQL1 OUT;
		
			EXEC(@SQL1);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep='P100', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke

			SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
		end

	PRINT 'Start Datenload: ' + convert(nvarchar, @Start, 113);
	PRINT 'Datenstand letzter Load: ' + convert(nvarchar, @LastLoadLocal, 113);
	PRINT 'Datenstand letzter Fullload: ' + convert(nvarchar, @LastFullLoadLocal, 113);
	PRINT 'Datenstand ct_Tabelle: '  + convert(nvarchar, @TableCTLastUpdateLocal, 113) ;

if (1 = 1)
goto Sprungmarke;	
Sprungmarke:

	if (dateadd(d,@DaysToFullLoad, @LastFullLoadLocal)<Getdate() 
		or @Datenweg=1 
		or datediff(d,@LastFullLoadLocal,@TableCTLastUpdateLocal)>6
		or @LastLoadLocal is null
		or @LastFullLoadLocal is null
		or @TableCTLastUpdateLocal is null
		or left(@Ladeverfahren,1)='F'
		) 
		and @FullloadYears <> 0
		and left(@Ladeverfahren,1) <>'D'
		and Len(@Fieldlist1)>0
		--and 2=1 --or 1=1
		Begin 
			SET @Ladeverfahren=concat('F',substring(@Ladeverfahren,2,100))
			PRINT 'Starte FullLoad'
		End
	else
		Begin
			SET @Ladeverfahren=concat('D',substring(@Ladeverfahren,2,100))
			PRINT 'Starte DeltaLoad'
		End

	If @Historisierung=0 
		Begin
			SET @Ladeverfahren=@Ladeverfahren+'O'
			PRINT 'Starte ohne Historisierung'
		End

	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

	Set @SQL= concat('
					Delay				:',@DELAY,'
					Zyklus				:',@DaysToFullLoad,'
					TestDurchLauf		:',@TestLoop,'
					Delta				:',@DeltaDays,'
					Fullload			:',@FullloadYears,'
					Ladeverfahren		:',@Ladeverfahren,'
					CDPOS_laden			:',@CDPOS_laden,'
					LastChangeFromTarget:',@LastChangeFromTarget,'
					HashAbgleich_ct		:',@HashAbgleich_ct,'
					Historisierung		:',@Historisierung,'
					PreProcessing		:',@PreProcessing,'
					PostProcessing		:',@PostProcessing,'
					TEMPPraefix			:',@TEMPPraefix)

	EXEC #LogStep @LogID=@LogID, 
						@LogTableProcessMode=@Ladeverfahren,
						@LogTableProcessStatus='PROCESS',
						@LogStep='CHANGE',
						@LogStepText='CHANGE',
						@LogStepSQL=@SQL,
						@LogStepRows=0,
						@LogStepStatus='FINISHED'

	If @PreProcessing=1 
		Begin

			if len(@SQL_PreProcessing1)>10
				Begin
					SET @StepText=Concat('','Ausführung Vorprozess 1')
					EXEC(@SQL_PreProcessing1);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='VP1', @LogStepText=@StepText, @LogTableProcessMode=@Ladeverfahren, @LogStepSQL=@SQL_PreProcessing1, @LogStepRows=@RowCount, @LogStepError=@Fehler
					if @Fehler>0
						goto Fehlermarke
					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
				End

			if len(@SQL_PreProcessing2)>10
				Begin
					SET @StepText=Concat('','Ausführung Vorprozess 2')
					EXEC(@SQL_PreProcessing2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='VP2', @LogStepText=@StepText, @LogStepSQL=@SQL_PreProcessing2, @LogStepRows=@RowCount, @LogStepError=@Fehler
					if @Fehler>0
						goto Fehlermarke
					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
				End

			if len(@SQL_PreProcessing3)>10
				Begin
					SET @StepText=Concat('','Ausführung Vorprozess 3')
					EXEC(@SQL_PreProcessing3);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='VP3', @LogStepText=@StepText, @LogStepSQL=@SQL_PreProcessing3, @LogStepRows=@RowCount, @LogStepError=@Fehler
					if @Fehler>0
						goto Fehlermarke
					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
				End

			if len(@SQL_PreProcessing4)>10
				Begin
					SET @StepText=Concat('','Ausführung Vorprozess 4')
					EXEC(@SQL_PreProcessing4);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='VP4', @LogStepText=@StepText, @LogStepSQL=@SQL_PreProcessing4, @LogStepRows=@RowCount, @LogStepError=@Fehler
					if @Fehler>0
						goto Fehlermarke
					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
				End

			if len(@SQL_PreProcessing5)>10
				Begin
					SET @StepText=Concat('','Ausführung Vorprozess 5')
					EXEC(@SQL_PreProcessing5);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='VP5', @LogStepText=@StepText, @LogStepSQL=@SQL_PreProcessing5, @LogStepRows=@RowCount, @LogStepError=@Fehler
					if @Fehler>0
						goto Fehlermarke
					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
				End
		end

	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

	if @StartStep='XP10'
		Goto XP10
	if @StartStep='XP20'
		Goto XP20
	if @StartStep='XP30'
		Goto XP30
	if @StartStep='XP40'
		Goto XP40
	if @StartStep='XP50'
		Goto XP50
	if @StartStep='XP60'
		Goto XP60
	if @StartStep='XP70'
		Goto XP70
	if @StartStep='XP80'
		Goto XP80
	if @StartStep='XP90'
		Goto XP90
	if @StartStep='XP100'
		Goto XP100
	if @StartStep='XP110'
		Goto XP110
	if @StartStep='XP120'
		Goto XP120
	if @StartStep='XP130'
		Goto XP130
	if @StartStep='XP140'
		Goto XP140
	if @StartStep='XP150'
		Goto XP150
	if @StartStep='XP160'
		Goto XP160
	if @StartStep='XP170'
		Goto XP170
	if @StartStep='XP380'
		Goto XP380
	if @StartStep='XP390'
		Goto XP390
	if @StartStep='XP400'
		Goto XP400
	if @StartStep='XP410'
		Goto XP410
	if @StartStep='XP420'
		Goto XP420
	if @StartStep='XP430'
		Goto XP430
	if @StartStep='XP440'
		Goto XP440
	if @StartStep='XP450'
		Goto XP450
	if @StartStep='XP460'
		Goto XP460
	if @StartStep='XP470'
		Goto XP470	
	if @StartStep='XP480'
		Goto XP480	
	if @StartStep='XP490'
		Goto XP490	
	if @StartStep='XP500'
		Goto XP500	
	if @StartStep='XP510'
		Goto XP510
	if @StartStep='XP520'
		Goto XP520
	if @StartStep='XP530'
		Goto XP530
	if @StartStep='XP540'
		Goto XP540
	if @StartStep='XP550'
		Goto XP550
	if @StartStep='XP560'
		Goto XP560
	if @StartStep='XP570'
		Goto XP570
	if @StartStep='NP1'
		Goto NP1
	if @StartStep='NP2'
		Goto NP2
	if @StartStep='NP3'
		Goto NP3
	if @StartStep='NP4'
		Goto NP4
	if @StartStep='NP5'
		Goto NP5
	if @StartStep='AP1'
		Goto AP1
	if @StartStep='AP2'
		Goto AP2
	if @StartStep='AP3'
		Goto AP3
	if @StartStep='AP4'
		Goto AP4
	if @StartStep='AP5'
		Goto AP5

	IF LEFT(@Ladeverfahren, 1) = 'F'
		BEGIN

XP10:

/*
Ist Filter auf LEN(ID) > 1 sinnvoll?
Immer Filter auf Jahr von Update/Createdate? - Sollten Jahre variabel sein?
*/

			SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''; SET @SQL4=''; SET @SQL5=''; SET @SQL6=''; SET @SQL7=''; SET @SQL8=''; SET @SQL9=''; SET @SQL10=''

			SET @StepPraefix = 'XP10'
			SET @StepText = CONCAT('Informationen aus [', @SQL_TableSourceString, '] extrahieren und in [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, CASE WHEN @Historisierung = 0 THEN '_FinalTable' ELSE '_Original' END, '] speichern.')

			SET @SQL = CONCAT('

				SELECT ', @TestLoop, '

			')

			IF @Historisierung = 0
				BEGIN

					SET @SQL1 = CONCAT('

							IDENTITY(BigInt,1,1) AS RowID
						,	ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS SchluesselID
						,	CAST(', REPLACE(@SQL_TableSourceID, '|x|', 't1.'),' AS nVarChar(200)) AS ', REPLACE(@SQL_TableTargetID, '|x|', '')

					)

					SET @SQL2 = ISNULL(REPLACE(@SQL_TableTargetDefinition1, '|x|', 't1.'), '')

					SET @SQL3 = ISNULL(REPLACE(@SQL_TableTargetDefinition2, '|x|', 't1.'), '')

					SET @SQL4 = ISNULL(REPLACE(@SQL_TableTargetDefinition3, '|x|', 't1.'), '')

					SET @SQL5 = ',	CAST(1 AS BigInt) AS Rang'

					SET @SQL7 = CONCAT('

						,	ISNULL(TRY_CAST(', REPLACE(@SQL_TableSourceCreateDate, '|x|', 't1.'), ' AS DateTime2), DateTime2FromParts(1900, 1, 1, 0, 0, 0, 0, 7)) AS ', REPLACE(@SQL_TableTargetValidFrom, '|x|', ''), '
						,	', CASE WHEN @ValidToStorno = 1 THEN CONCAT('ISNULL(TRY_CAST(', REPLACE(@SQL_TableSourceStornoDate, '|x|', 't1.'), ' AS DateTime2), DateTime2FromParts(2099, 12, 31, 23, 59, 59, 0, 7))') ELSE 'DateTime2FromParts(2099, 12, 31, 23, 59, 59, 0, 7)' END, ' AS ', REPLACE(@SQL_TableTargetValidTo, '|x|', '')

					)

					SET @SQL9 = CONCAT('

						,	CAST(0 AS Int)  AS ', REPLACE(@SQL_TableTargetDeleteFlag, '|x|', ''), '
						,	DateTime2FromParts(2099, 12, 31, 23, 59, 59, 0, 7) AS ', REPLACE(@SQL_TableTargetDeleteDate, '|x|', ''), '
						,	CAST(1 AS Int)  AS LastChangeOnDate
						,	CAST(SYSUTCDATETIME() AT TIME ZONE ''UTC'' AT TIME ZONE ''Central European Standard Time'' AS DateTime2) AS LastChange

					')

				END

			IF @Historisierung = 1
				BEGIN

					SET @SQL1 = CONCAT('

						CAST(', REPLACE(@SQL_TableSourceID, '|x|', 't1.'),' AS nVarChar(200)) AS ', REPLACE(@SQL_TableTargetID, '|x|', '')

					)

					SET @SQL2 = CONCAT(',	', REPLACE(@FieldList2, '|x|', 't1.'))

					SET @SQL9 = ',	SYSUTCDATETIME() AS TimestampUTC'

				END

			SET @SQL6 = CONCAT('

				,	CAST(HASHBYTES(''SHA1'', (SELECT ', Replace(@Fieldlist2, '|x|', 't1.'), CASE WHEN @SQL_TableSourceStornoField = '' THEN '' ELSE CONCAT(',TRIM(', REPLACE(@SQL_TableSourceStornoField, '|x|', 't1.'), ') AS StornoField') END, ' FOR XML RAW)) AS VarBinary(100)) AS HashID

			')

			SET @SQL8 = CONCAT('

				,	CAST(', REPLACE(@SQL_TableSourceCreateDate, '|x|', 't1.'), ' AS DateTime2) AS ', REPLACE(@SQL_TableTargetCreateDate, '|x|', ''), '
				,	CAST(', REPLACE(@SQL_TableSourceUpDate, '|x|', 't1.'), ' AS DateTime2) AS ', REPLACE(@SQL_TableTargetUpDate, '|x|', ''), '
				,	', REPLACE(@SQL_TableSourceStornoFlag, '|x|', 't1.'), ' AS ', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), '
				,	CAST(', REPLACE(@SQL_TableSourceStornoDate, '|x|', 't1.'), ' AS DateTime2) AS ', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), '

			')

			SET @SQL10 = CONCAT('

				INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, CASE WHEN @Historisierung = 0 THEN '_FinalTable' ELSE '_Original' END, '

				FROM ', @SQL_TableSourceString,' AS t1
				', REPLACE(@SQL_TableSource_Join, '|x|', 't1.'), '

				WHERE LEN(', REPLACE(@SQL_TableSourceID, '|x|', 't1.'), ') > 1
				AND (YEAR(', REPLACE(@SQL_TableSourceUpDate, '|x|', 't1.'), ') BETWEEN 1990 AND 2099 OR YEAR(', REPLACE(@SQL_TableSourceCreateDate, '|x|', 't1.'), ') BETWEEN 1990 AND 2099)
				', CASE WHEN LEN(@SQL_TableSource_Where) > 0 THEN CONCAT(' AND ', REPLACE(@SQL_TableSource_Where, '|x|', 't1.')) ELSE '' END , '

			')

			EXEC(@SQL+@SQL1+@SQL2+@SQL3+@SQL4+@SQL5+@SQL6+@SQL7+@SQL8+@SQL9+@SQL10);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepSQL1 = @SQL1, @LogStepSQL2 = @SQL2, @LogStepSQL3 = @SQL3, @LogStepSQL4 = @SQL4, @LogStepSQL5 = @SQL5, @LogStepSQL6 = @SQL6, @LogStepSQL7 = @SQL7, @LogStepSQL8 = @SQL8, @LogStepSQL9 = @SQL9, @LogStepSQL10 = @SQL10, @LogStepRows = @RowCount, @LogStepError = @Fehler

			IF @Fehler > 0
				GoTo Fehlermarke

			SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''; SET @SQL4=''; SET @SQL5=''; SET @SQL6=''; SET @SQL7=''; SET @SQL8=''; SET @SQL9=''; SET @SQL10=''

			IF @Historisierung = 1
				BEGIN

XP20:

					SET @StepPraefix = 'XP20'
					SET @StepText = CONCAT('Zeitstempel der Daten aus [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_Original] in @SnapshotTimestampUTC speichern.')

					SET @SQL = CONCAT('

						SELECT @SnapshotTimestampUTC = (SELECT TOP 1 TimestampUTC AS SnapshotTimestampUTC FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_Original)

					')

					EXEC sp_EXECutesql @SQL, N'@SnapshotTimestampUTC DateTime2 OUT', @SnapshotTimestampUTC OUT;
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepRows = @RowCount, @LogStepError = @Fehler, @LogTableTime = @SnapshotTimestampUTC

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP30:

					SET @Zaehler = 0
					SET @Praefix = '__ct'
					SET @SQL10 = ''

					IF @InsertInto = 1
						BEGIN

							SET @StepPraefix = 'XP30'
							SET @StepText = CONCAT('Tabelle [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix,'_ct_1] initial anlegen.')

							-- sollte es die ct-Tabelle nicht geben, wird schon in P20 rausgesprungen -> muss hier nicht mehr abgefangen werden
							SET @SQL= CONCAT('

								SELECT TOP 0
									CAST(NULL AS VarChar(35)) AS ChangeSeq
								,	CAST(NULL AS VarChar(1)) AS ChangeTyp
								,	CAST(NULL AS DateTime2) AS ChangeTime
								,	CAST(NULL AS VarChar(12)) AS ChangeSource
								,	CAST(', REPLACE(@SQL_TableSourceID, '|x|', ''), ' AS nVarChar(200)) AS ', REPLACE(@SQL_TableTargetID, '|x|', ''), '
								,	', REPLACE(@Fieldlist1, '|x|', ''), '
								,	CAST(NULL AS VarBinary(100)) AS HashID
								,	CAST(NULL AS DateTime2) AS ', REPLACE(@SQL_TableTargetCreateDate, '|x|', ''), '
								,	CAST(NULL AS DateTime2) AS ', REPLACE(@SQL_TableTargetUpDate, '|x|', ''), '
								,	CAST(NULL AS Int) AS ', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), '
								,	CAST(NULL AS DateTime2) AS ', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), '

								INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_1

								FROM ', @SQL_TableSourceString, @Praefix, '

							')

							EXEC(@SQL);
							SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
							EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepRows = @RowCount, @LogStepError = @Fehler

							IF @Fehler > 0
								GoTo Fehlermarke

							SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

						END

					WHILE OBJECT_ID(CONCAT(@SQL_TableSourceString, @Praefix), 'U') IS NOT NULL 
						BEGIN

							SET @StepPraefix = CONCAT('XP30_ct_',  @Zaehler + 1)
							SET @StepText = CONCAT('Relevante Änderungen aus [', @SQL_TableSourceString, @Praefix, '] extrahieren und in [', CASE WHEN @InsertInto = 1 THEN CONCAT(@SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct] einfügen.') ELSE CONCAT(@SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_1_', @Zaehler, '] speichern.') END, ' (Zeitstempel: ', @SnapshotTimestampUTC, ' UTC)')

							SET @SQL = CONCAT(

								CASE WHEN @InsertInto = 1 THEN CONCAT('INSERT INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_1') ELSE '' END, '

								SELECT ', @TestLoop, '
									header__change_seq AS ChangeSeq
								,	header__change_oper AS ChangeTyp
								,	CAST(header__timestamp AT TIME ZONE ''UTC'' AT TIME ZONE ''Central European Standard Time'' AS DateTime2) AS ChangeTime
								,	''', @Praefix, ''' AS ChangeSource
								,	CAST(', REPLACE(@SQL_TableSourceID, '|x|', 't1.'), ' AS nVarChar(200)) AS ', REPLACE(@SQL_TableTargetID, '|x|', ''), '
								,	', REPLACE(@Fieldlist2, '|x|', 't1.'), '
								,	HASHBYTES(''SHA1'', (SELECT ', Replace(@Fieldlist2, '|x|', 't1.'), CASE WHEN @SQL_TableSourceStornoField = '' THEN '' ELSE CONCAT(',TRIM(', REPLACE(@SQL_TableSourceStornoField, '|x|', 't1.'), ') AS StornoField') END, ' FOR XML RAW)) AS HashID
								,	', REPLACE(@SQL_TableSourceCreateDate, '|x|', 't1.'), ' AS ', REPLACE(@SQL_TableTargetCreateDate, '|x|', ''), '
								,	', REPLACE(@SQL_TableSourceUpDate, '|x|', 't1.'), ' AS ', REPLACE(@SQL_TableTargetUpDate, '|x|', ''), '
								,	', REPLACE(@SQL_TableSourceStornoFlag, '|x|', 't1.'), ' AS ', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), '
								,	', REPLACE(@SQL_TableSourceStornoDate, '|x|', 't1.'), ' AS ', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), '

							')

							SET @SQL1 = CONCAT(

								CASE WHEN @InsertInto = 1 THEN '' ELSE CONCAT('INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_1_', @Zaehler) END, '

								FROM ', @SQL_TableSourceString, @Praefix,' AS t1
								', REPLACE(@SQL_TableSource_Join, '|x|', 't1.'), '

								WHERE t1.header__timestamp <= CAST(''' + CONVERT(nVarChar, @SnapshotTimestampUTC, 126) + ''' AS DateTime2)
								', CASE WHEN LEN(@SQL_TableSource_Where) > 0 THEN CONCAT(' AND ', REPLACE(@SQL_TableSource_Where, '|x|', 't1.')) ELSE '' END, '

							')

							EXEC(@SQL+@SQL1);
							SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
							EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepSQL1 = @SQL1, @LogStepRows = @RowCount, @LogStepError = @Fehler

							IF @Fehler > 0
								GoTo Fehlermarke

							SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

							IF @InsertInto = 0
								SET @SQL10 = CONCAT(@SQL10, ',', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_1_', @Zaehler)

							SET @Zaehler = @Zaehler + 1

							IF @Praefix='__ct'
								BEGIN 
									SET @Praefix = '__ct__bak'
								END
							ELSE
								BEGIN
									SET @Praefix = CONCAT('__ct__bak_', @Zaehler - 1)
								END

						END -- WHILE OBJECT_ID(CONCAT(@SQL_TableSourceString,@Praefix), 'U') IS NOT NULL

					/* -------------------------------------------------------------------------------------------

					IF "CDPOS soll verwendet werden = Ja"

					SET @StepPraefix = 'XP30_CDPOS'

					...

					--------------------------------------------------------------------------------------------*/

XP40:

					SET @StepPraefix = 'XP40'
					SET @StepText = CASE WHEN @InsertInto = 1 THEN CONCAT('Datensatz aus [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_Original] in Tabelle [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_1] einfügen.') ELSE CONCAT('Tabelle [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_1] erstellen.') END

					SET @SQL = CONCAT(

						CASE WHEN @InsertInto = 1 THEN CONCAT('INSERT INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_1') ELSE '' END, '

						SELECT
							REPLICATE(''9'', 35) AS ChangeSeq
						,	''O'' AS ChangeTyp
						,	CAST(TimestampUTC AT TIME ZONE ''UTC'' AT TIME ZONE ''Central European Standard Time'' AS DateTime2) AS ChangeTime
						,	''Original'' AS ChangeSource
						,	', REPLACE(@SQL_TableTargetID, '|x|', ''), '
						,	', REPLACE(@Fieldlist1, '|x|', ''), '
						,	HashID
						,	', REPLACE(@SQL_TableTargetCreateDate, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetUpDate, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), '

						', CASE WHEN @InsertInto = 1 THEN '' ELSE CONCAT('INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_1') END, '

						FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_Original

					')

					IF @InsertInto = 0
						BEGIN

							SELECT
								@SQL1 = COALESCE(@SQL1 + N'', N'')
										+ CHAR(10)
										+ 'UNION ALL' + CHAR(10)
										+ CHAR(10)
										+ 'SELECT' + CHAR(10)
										+ '	ChangeSeq' + CHAR(10)
										+ ',	ChangeTyp' + CHAR(10)
										+ ',	ChangeTime' + CHAR(10)
										+ ',	CAST(ChangeSource AS VarChar(12)) AS ChangeSource' + CHAR(10)
										+ ',	' + REPLACE(@SQL_TableTargetID, '|x|', '') + CHAR(10)
										+ ',	' + REPLACE(@Fieldlist1, '|x|', '') + CHAR(10)
										+ ',	HashID' + CHAR(10)
										+ ',	' + REPLACE(@SQL_TableTargetCreateDate, '|x|', '') + CHAR(10)
										+ ',	' + REPLACE(@SQL_TableTargetUpDate, '|x|', '') + CHAR(10)
										+ ',	' + REPLACE(@SQL_TableTargetStornoFlag, '|x|', '') + CHAR(10)
										+ ',	' + REPLACE(@SQL_TableTargetStornoDate, '|x|', '') + CHAR(10)
										+ 'FROM ' + t1.Spalte + CHAR(10)
							FROM (
								SELECT
									CAST(VALUE AS nVarChar(200)) AS Spalte
								FROM STRING_SPLIT(@SQL10, ',')
							) AS t1
							WHERE LEN(t1.Spalte) > 0
						END

					EXEC(@SQL+@SQL1);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepSQL1 = @SQL1, @LogStepRows = @RowCount, @LogStepError = @Fehler

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''; SET @SQL10='';

XP50:

					SET @StepPraefix = 'XP50'
					SET @StepText = CONCAT('Zeitstempel vom letzten verarbeiteten Eintrag aus [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_1] in @TableCTLastUpdateLocal speichern.')

					SET @SQL = CONCAT('

						SELECT @TableCTLastUpdateLocal = (SELECT MAX(ChangeTime) AS Zeitstempel FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_1 WHERE ChangeSource != ''Original'')

					')

					EXEC sp_EXECutesql @SQL, N'@TableCTLastUpdateLocal DateTime2 OUT', @TableCTLastUpdateLocal OUT;
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepRows = @RowCount, @LogStepError = @Fehler, @LogTableTime = @TableCTLastUpdateLocal

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''


XP60:
-- INDEX auf @SQL_TableTargetID? - siehe XP20 alt

XP70:

					SET @StepPraefix = 'XP70'
					SET @StepText = CONCAT('Spalte [SeqID] aus Tabelle [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_1] bestimmen und Ergebnis in [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_2] speichern.')

					SET @SQL = CONCAT('

						SELECT
							CAST(ROW_NUMBER() OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY ChangeSeq ASC, ChangeTyp ASC) * 2 AS BigInt) AS SeqID
						,	ChangeSeq
						,	ChangeTyp
						,	ChangeTime
						,	ChangeSource
						,	', REPLACE(@SQL_TableTargetID, '|x|', ''), '
						,	', REPLACE(@Fieldlist1, '|x|', ''), '
						,	HashID
						,	', REPLACE(@SQL_TableTargetCreateDate, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetUpDate, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), '

						INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_2

						FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_1

					')

					EXEC(@SQL);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepRows = @RowCount, @LogStepError = @Fehler

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP80:
-- INDEX auf @SQL_TableTargetID und SeqID? --> ExecutionPlan schlägt keine Indizes vor.

XP90:

					SET @StepPraefix = 'XP90'
					SET @StepText = CONCAT('Spalte [Add_Operation] aus Tabelle [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_2] bestimmen und Ergebnis in [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_3] speichern.')

					SET @SQL = CONCAT('

						SELECT
							t1.SeqID
						,	t1.ChangeSeq
						,	t1.ChangeTyp
						,	CASE
								WHEN tv.HashID IS NULL AND t1.ChangeTyp = ''I'' AND ', REPLACE(@SQL_TableTargetCreateDate, '|x|', 't1.'), ' < t1.ChangeTime
								THEN ', REPLACE(@SQL_TableTargetCreateDate, '|x|', 't1.'), '

								ELSE t1.ChangeTime
							END AS ChangeTime
						,	tv.ChangeTime AS ChangeTime_Vorgaenger
						,	t1.ChangeSource
						,	', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), '
						,	', REPLACE(@Fieldlist1, '|x|', 't1.'), '
						,	t1.HashID
						,	', REPLACE(@SQL_TableTargetCreateDate, '|x|', 't1.'), '
						,	', REPLACE(@SQL_TableTargetUpDate, '|x|', 't1.'), '
						,	', REPLACE(@SQL_TableTargetStornoFlag, '|x|', 't1.'), '
						,	', REPLACE(@SQL_TableTargetStornoDate, '|x|', 't1.'), '

					')

					SET @SQL1 = '

						,	CASE
								-- Aktuellester Wert ist nicht O oder nicht D --> ein DELETE muss danach eingefügt werden
								WHEN tn.HashID IS NULL AND t1.ChangeTyp NOT IN (''O'', ''D'')
								THEN 1

								-- Original-Wert (O), direkt nach einem DELETE --> ein INSERT muss dazwischen eingefügt werden
								WHEN t1.ChangeTyp = ''O'' AND tv.ChangeTyp = ''D''
								THEN 2

								-- Original-Wert (O), direkt nach einem INS/UP mit anderem Hash --> ein UPDATE muss dazwischen eingefügt werden
								WHEN t1.ChangeTyp = ''O'' AND tv.ChangeTyp != ''D'' AND t1.HashID != tv.HashID
								THEN 22

								-- Erster Eintrag ist kein INSERT --> ein INSERT muss davor eingefügt werden
								WHEN tv.HashID IS NULL AND t1.ChangeTyp != ''I''
								THEN 3

								-- DELETE direkt nach einem DELETE --> ein INSERT muss dazwischen eingefügt werden
								WHEN t1.ChangeTyp = ''D'' AND tv.ChangeTyp = ''D''
								THEN 4

								-- DELETE direkt nach einem INS/UP aber anderer Hash --> ein UPDATE muss dazwischen eingefügt werden
								WHEN t1.ChangeTyp = ''D'' AND tv.ChangeTyp IN (''I'', ''U'') AND t1.HashID != tv.HashID
								THEN 5

								-- INSERT direkt nach einem INS/UP --> ein DELETE muss dazwischen eingefügt werden
								WHEN t1.ChangeTyp = ''I'' AND tv.ChangeTyp IN (''I'', ''U'')
								THEN 6

								-- BEFORE direkt nach einem DELETE --> ein INSERT muss dazwischen eingefügt werden
								WHEN t1.ChangeTyp = ''B'' AND tv.ChangeTyp = ''D''
								THEN 7

								-- BEFORE direkt nach einem INS/UP aber anderer Hash --> ein UPDATE muss dazwischen eingefügt werden
								WHEN t1.ChangeTyp = ''B'' AND tv.ChangeTyp IN (''I'', ''U'') AND t1.HashID != tv.HashID
								THEN 8

								ELSE 0
							END AS Add_Operation

					'

					SET @SQL2 = CONCAT('

						INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_3

						FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_2 AS t1

						LEFT JOIN ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_2 AS tv -- Vorgänger
						ON	', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), ' = ', REPLACE(@SQL_TableTargetID, '|x|', 'tv.'), '
						AND	t1.SeqID = tv.SeqID + 2

						LEFT JOIN ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_2 AS tn -- Nachfolger
						ON	', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), ' = ', REPLACE(@SQL_TableTargetID, '|x|', 'tn.'), '
						AND	t1.SeqID = tn.SeqID - 2

					')

					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepSQL1 = @SQL1, @LogStepSQL2 = @SQL2, @LogStepRows = @RowCount, @LogStepError = @Fehler

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP100:
					-- Vorbereitung: Zeiteinheiten zum Einfügen von fehlenden Zeitscheiben einheitlich in Minuten umrechnen
					IF @AddDeleteAfterLastEntry > 0
						SET @AddDeleteAfterLastEntry = @AddDeleteAfterLastEntry * 1440
					ELSE
						SET @AddDeleteAfterLastEntry = @AddDeleteAfterLastEntry * -1

					IF @AddInsertBeforeEntry > 0
						SET @AddInsertBeforeEntry = @AddInsertBeforeEntry * 1440
					ELSE
						SET @AddInsertBeforeEntry = @AddInsertBeforeEntry * -1

					IF @AddUpdateBeforeEntry > 0
						SET @AddUpdateBeforeEntry = @AddUpdateBeforeEntry * 1440
					ELSE
						SET @AddUpdateBeforeEntry = @AddUpdateBeforeEntry * -1

					IF @AddDeleteBeforeEntry > 0
						SET @AddDeleteBeforeEntry = @AddDeleteBeforeEntry * 1440
					ELSE
						SET @AddDeleteBeforeEntry = @AddDeleteBeforeEntry * -1

					-- Vorbereitung: @Fieldlist3 erstellen, um fehlendes DELETE richtig einzufügen
					SET @SQL = CONCAT('

						SELECT
							@FieldList3 = COALESCE(@FieldList3+N'''', N'''') + '','' + CHAR(9) + ''CASE WHEN t1.Add_Operation IN (6) THEN '' + REPLACE(t1.Spalte, ''|x|'', ''tv.'') + '' ELSE '' + REPLACE(t1.Spalte, ''|x|'', ''t1.'') + '' END AS '' + REPLACE(t1.Spalte, ''|x|'', '''') + CHAR(10)
						FROM (
							SELECT
								CAST(VALUE AS nVarChar(50)) AS Spalte 
							FROM STRING_SPLIT(''',@Fieldlist1,''', '','')
						) AS t1

					')

					EXEC sp_EXECutesql @SQL, N'@FieldList3 nVarChar(max) OUT', @Fieldlist3 OUT;
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

					-- Eigentlicher Schritt XP100
					SET @StepPraefix = 'XP100'
					SET @StepText = CONCAT('Fehlende Zeitscheiben bestimmen und in Tabelle [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_3] einfügen.')

					SET @SQL = CONCAT('

						INSERT INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_3

						SELECT
							CASE
								WHEN t1.Add_Operation IN (1)
								THEN t1.SeqID + 1

								ELSE t1.SeqID - 1
							END AS SeqID
						,	CASE
								WHEN t1.Add_Operation IN (1)
								THEN CONCAT(LEFT(t1.ChangeSeq, 17), RIGHT(CONCAT(REPLICATE(''0'', 18), CAST(CAST(RIGHT(t1.ChangeSeq, 18) AS BigInt) + 1 AS VarChar(19))), 18))

								ELSE CONCAT(LEFT(t1.ChangeSeq, 17), RIGHT(CONCAT(REPLICATE(''0'', 18), CAST(CAST(RIGHT(t1.ChangeSeq, 18) AS BigInt) - 1 AS VarChar(19))), 18))
							END AS ChangeSeq
						,	CASE
								WHEN t1.Add_Operation IN (2, 3, 4, 7)
								THEN ''I''

								WHEN t1.Add_Operation IN (5, 8, 22)
								THEN ''U''

								WHEN t1.Add_Operation IN (1, 6)
								THEN ''D''

								ELSE t1.ChangeTyp
							END AS ChangeTyp
						,	CASE
								WHEN t1.Add_Operation IN (1)
								THEN DATEADD(Minute, ', @AddDeleteAfterLastEntry, ', t1.ChangeTime)

								WHEN t1.Add_Operation IN (3) AND DATEADD(Minute, -', @AddInsertBeforeEntry, ', t1.ChangeTime) > ', REPLACE(@SQL_TableTargetCreateDate, '|x|', 't1.'), '
								THEN ', REPLACE(@SQL_TableTargetCreateDate, '|x|', 't1.'), '
								
								WHEN t1.Add_Operation IN (2, 3, 4, 7) AND DATEADD(Minute, -', @AddInsertBeforeEntry, ', t1.ChangeTime) > ISNULL(t1.ChangeTime_Vorgaenger, DateTime2FromParts(1900, 01, 01, 12, 00, 00, 00, 7))
								THEN DATEADD(Minute, -', @AddInsertBeforeEntry, ', t1.ChangeTime)

								WHEN t1.Add_Operation IN (5, 8, 22) AND DATEADD(Minute, -', @AddUpdateBeforeEntry, ', t1.ChangeTime) > ISNULL(t1.ChangeTime_Vorgaenger, DateTime2FromParts(1900, 01, 01, 12, 00, 00, 00, 7))
								THEN DATEADD(Minute, -', @AddUpdateBeforeEntry, ', t1.ChangeTime)

								WHEN t1.Add_Operation IN (6) AND DATEADD(Minute, -', @AddDeleteBeforeEntry, ', t1.ChangeTime) > ISNULL(t1.ChangeTime_Vorgaenger, DateTime2FromParts(1900, 01, 01, 12, 00, 00, 00, 7))
								THEN DATEADD(Minute, -', @AddDeleteBeforeEntry, ', t1.ChangeTime)

								ELSE DATEADD(Second, 1, t1.ChangeTime_Vorgaenger)
							END AS ChangeTime
						,	NULL AS ChangeTime_Vorgaenger
						,	CASE
								WHEN t1.Add_Operation IN (2, 3, 4, 7)
								THEN ''neues Insert''

								WHEN t1.Add_Operation IN (5, 8, 22)
								THEN ''neues Update''

								WHEN t1.Add_Operation IN (1, 6)
								THEN ''neues Delete''

								ELSE t1.ChangeSource
							END AS ChangeSource
						,	', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), '

					')

					SET @SQL1 = CONCAT('

						', @Fieldlist3, '

					')

					SET @SQL2 = CONCAT('

						,	CASE WHEN t1.Add_Operation IN (6) THEN tv.HashID ELSE t1.HashID END AS HashID
						,	CASE WHEN t1.Add_Operation IN (6) THEN ', REPLACE(@SQL_TableTargetCreateDate, '|x|', 'tv.'), ' ELSE ', REPLACE(@SQL_TableTargetCreateDate, '|x|', 't1.'), ' END AS ', REPLACE(@SQL_TableTargetCreateDate, '|x|', ''), '
						,	CASE WHEN t1.Add_Operation IN (6) THEN ', REPLACE(@SQL_TableTargetUpDate, '|x|', 'tv.'), ' ELSE ', REPLACE(@SQL_TableTargetUpDate, '|x|', 't1.'), ' END AS ', REPLACE(@SQL_TableTargetUpDate, '|x|', ''), '
						,	CASE WHEN t1.Add_Operation IN (6) THEN ', REPLACE(@SQL_TableTargetStornoFlag, '|x|', 'tv.'), ' ELSE ', REPLACE(@SQL_TableTargetStornoFlag, '|x|', 't1.'), ' END AS ', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), '
						,	CASE WHEN t1.Add_Operation IN (6) THEN ', REPLACE(@SQL_TableTargetStornoDate, '|x|', 'tv.'), ' ELSE ', REPLACE(@SQL_TableTargetStornoDate, '|x|', 't1.'), ' END AS ', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), '
						,	t1.Add_Operation

						FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_3 AS t1

						LEFT JOIN ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_3 AS tv -- Vorgänger
						ON ', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), ' = ', REPLACE(@SQL_TableTargetID, '|x|', 'tv.'), '
						AND	t1.SeqID = tv.SeqID + 2

						WHERE t1.Add_Operation > 0

					')

					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepSQL1 = @SQL1, @LogStepSQL2 = @SQL2, @LogStepRows = @RowCount, @LogStepError = @Fehler

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP110:

					SET @StepPraefix = 'XP110'
					SET @StepText = CONCAT('Spalte [LastChangeOnDate] aus Tabelle [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_3] bestimmen, Tabelle filtern und Ergebnis in [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_4] speichern.')

					SET @SQL = CONCAT('

						SELECT
							t1.SeqID
						,	t1.ChangeSeq
						,	t1.ChangeTyp
						,	t1.ChangeTime
						,	t1.ChangeSource
						,	', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), '
						,	', REPLACE(@SQL_TableTargetStornoFlag, '|x|', 't1.'), '
						,	', REPLACE(@SQL_TableTargetStornoDate, '|x|', 't1.'), '
						,	t1.HashID
						,	CASE WHEN t2.LastChangeOnDate = 1 THEN 1 ELSE 0 END AS LastChangeOnDate

						INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_4

						FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_3 AS t1

						INNER JOIN (
							SELECT
								', REPLACE(@SQL_TableTargetID, '|x|', ''), '
							,	ChangeTyp
							,	ChangeTime
							,	ROW_NUMBER() OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ', CAST(ChangeTime AS Date) ORDER BY SeqID DESC) AS LastChangeOnDate
							FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_3
						) AS t2
						ON	', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), ' = ', REPLACE(@SQL_TableTargetID, '|x|', 't2.'), '
						AND	t1.ChangeTime = t2.ChangeTime
						AND t1.ChangeTyp = t2.ChangeTyp
						AND ', CASE WHEN @LastChangeOnDate = 1 THEN 't2.LastChangeOnDate = 1' ELSE 't1.ChangeTyp != ''B''' END

					)

					EXEC(@SQL);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepRows = @RowCount, @LogStepError = @Fehler

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP115:

					SET @StepPraefix = 'XP115'
					SET @StepText = CONCAT('Spalte [SeqID] aus Tabelle [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_4] neu bestimmen und Ergebnis in [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_5] speichern.')

					SET @SQL = CONCAT('

						SELECT
							CAST(ROW_NUMBER() OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY ChangeSeq ASC, ChangeTyp ASC) AS BigInt) AS SeqID
						,	ChangeSeq
						,	ChangeTyp
						,	ChangeTime
						,	ChangeSource
						,	', REPLACE(@SQL_TableTargetID, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), '
						,	HashID
						,	LastChangeOnDate

						INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_5

						FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_4

					')

					EXEC(@SQL);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepRows = @RowCount, @LogStepError = @Fehler

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP120:

					-- Vorbereitung: Zeiteinheit zum ignorieren von Änderungen in Sekunden umrechnen
					IF @IgnoreChangesWithinTime > 0
						SET @IgnoreChangesWithinTime = @IgnoreChangesWithinTime * 60
					ELSE
						SET @IgnoreChangesWithinTime = @IgnoreChangesWithinTime * -1

					-- Eigentlicher Schritt XP120
					SET @StepPraefix = 'XP120'
					SET @StepText = CONCAT('Datensätze mit Hashbereich- und Stornowechsel in Tabelle [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_5] markieren und in [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_6] speichern.')

					SET @SQL = CONCAT('

						SELECT
							t1.SeqID
						,	t1.ChangeSeq
						,	t1.ChangeTyp
						,	t1.ChangeTime
						,	t1.ChangeSource
						,	', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), '
						,	', REPLACE(@SQL_TableTargetStornoFlag, '|x|', 't1.'), '
						,	', REPLACE(@SQL_TableTargetStornoDate, '|x|', 't1.'), '
						,	t1.HashID
						,	t1.LastChangeOnDate

						,	CASE
								WHEN	(
											t1.ChangeTyp IN (''I'', ''U'')
										AND DATEDIFF_BIG(Second, t1.ChangeTime, ISNULL(tn.ChangeTime, DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7))) < ', @IgnoreChangesWithinTime, '
										)

									OR	(
											t1.ChangeTyp IN (''I'', ''U'', ''O'')
										AND	ISNULL(tv.ChangeTyp, '''') IN (''I'', ''U'')
										AND	t1.HashID = ISNULL(tv.HashID, 1)
										)

									OR	(
											t1.ChangeTyp IN (''I'', ''U'', ''O'')
										AND	ISNULL(tv.ChangeTyp, '''') = ''D''
										AND	DATEDIFF_BIG(Second, ISNULL(tv.ChangeTime, DateTime2FromParts(1900, 01, 01, 00, 00, 00, 00, 7)), t1.ChangeTime) < ', @IgnoreChangesWithinTime, '
										AND t1.HashID = ISNULL(tv.HashID, 1)
										)

									OR	(
											t1.ChangeTyp = ''D''
										AND ISNULL(tn.ChangeTyp, '''') IN (''I'', ''U'', ''O'')
										AND DATEDIFF_BIG(Second, t1.ChangeTime, ISNULL(tn.ChangeTime, DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7))) < ', @IgnoreChangesWithinTime, '
										)

									OR	(
											t1.ChangeTyp = ''D''
										AND	ISNULL(tv.ChangeTyp, '''') = ''I''
										AND DATEDIFF_BIG(Second, ISNULL(tv.ChangeTime, DateTime2FromParts(1900, 01, 01, 00, 00, 00, 00, 7)), t1.ChangeTime) < ', @IgnoreChangesWithinTime, '
										)

									OR	(
											t1.ChangeTyp = ''D''
										AND ISNULL(tv.ChangeTyp, '''') = ''D''
										)
								THEN 0
								ELSE 1
							END AS HashBereichWechsel

						,	CASE
								WHEN ', REPLACE(@SQL_TableTargetStornoFlag, '|x|', 't1.'), ' = 1 AND ISNULL(', REPLACE(@SQL_TableTargetStornoFlag, '|x|', 'tv.'), ', 1) = 0
								THEN 1
								ELSE 0
							END AS StornoWechsel

						INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_6

						FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_5 AS t1

						LEFT JOIN ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_5 AS tv -- Vorgänger
						ON	', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), ' = ', REPLACE(@SQL_TableTargetID, '|x|', 'tv.'), '
						AND	t1.SeqID = tv.SeqID + 1

						LEFT JOIN ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_5 AS tn -- Nachfolger
						ON	', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), ' = ', REPLACE(@SQL_TableTargetID, '|x|', 'tn.'), '
						AND	t1.SeqID = tn.SeqID - 1

					')

					EXEC(@SQL);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepRows = @RowCount, @LogStepError = @Fehler

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
/*
XP115T:

					SET @StepPraefix = 'XP115T'
					SET @StepText = CONCAT('Index [x', REPLACE(@SQL_TableTargetID, '|x|', ''), '_ct_4] für Tabelle [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_4] anlegen.')

					SET @SQL = CONCAT('

						CREATE CLUSTERED INDEX x', REPLACE(@SQL_TableTargetID, '|x|', ''), '_ct_4 ON ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_4
						(', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ASC, SeqID ASC) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

					')

					EXEC(@SQL);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepRows = @RowCount, @LogStepError = @Fehler

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP120T:

--					-- Vorbereitung: Zeiteinheit zum ignorieren von Änderungen in Sekunden umrechnen
--					IF @IgnoreChangesWithinTime > 0
--						SET @IgnoreChangesWithinTime = @IgnoreChangesWithinTime * 60
--					ELSE
--						SET @IgnoreChangesWithinTime = @IgnoreChangesWithinTime * -1

					-- Eigentlicher Schritt XP120
					SET @StepPraefix = 'XP120T'
					SET @StepText = CONCAT('Datensätze mit Hashbereich- und Stornowechsel in Tabelle [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_4] markieren und in [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_6T] speichern.')

					SET @SQL = CONCAT('

						SELECT
							SeqID
						,	ChangeSeq
						,	ChangeTyp
						,	ChangeTime
						,	ChangeSource
						,	', REPLACE(@SQL_TableTargetID, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), '
						,	HashID
						,	LastChangeOnDate

						,	CASE
								WHEN	(
											ChangeTyp IN (''I'', ''U'')
										AND DATEDIFF_BIG(Second, ChangeTime, ISNULL(LEAD(ChangeTime) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), DateTime2FromParts(2100, 01, 01, 12, 00, 00, 00, 7))) < ', @IgnoreChangesWithinTime, '
										)

									OR	(
											ChangeTyp IN (''I'', ''U'', ''O'')
										AND	ISNULL(LAG(ChangeTyp) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), '''') IN (''I'', ''U'')
										AND	HashID = ISNULL(LAG(HashID) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), 1)
										)

									OR	(
											ChangeTyp IN (''I'', ''U'', ''O'')
										AND	ISNULL(LAG(ChangeTyp) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), '''') = ''D''
										AND	DATEDIFF_BIG(Second, ISNULL(LAG(ChangeTime) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), DateTime2FromParts(1900, 01, 01, 12, 00, 00, 00, 7)), ChangeTime) < ', @IgnoreChangesWithinTime, '
										AND HashID = ISNULL(LAG(HashID) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), 1)
										)

									OR	(
											ChangeTyp = ''D''
										AND ISNULL(LEAD(ChangeTyp) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), '''') IN (''I'', ''U'', ''O'')
										AND DATEDIFF_BIG(Second, ChangeTime, ISNULL(LEAD(ChangeTime) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), DateTime2FromParts(2100, 01, 01, 12, 00, 00, 00, 7))) < ', @IgnoreChangesWithinTime, '
										)

									OR	(
											ChangeTyp = ''D''
										AND	ISNULL(LAG(ChangeTyp) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), '''') = ''I''
										AND DATEDIFF_BIG(Second, ISNULL(LAG(ChangeTime) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), DateTime2FromParts(1900, 01, 01, 12, 00, 00, 00, 7), ChangeTime) < ', @IgnoreChangesWithinTime, '
										)

									OR	(
											ChangeTyp = ''D''
										AND ISNULL(LAG(ChangeTyp) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), '''') = ''D''
										)
								THEN 0
								ELSE 1
							END AS HashBereichWechsel

						,	CASE
								WHEN ', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), ' = 1 AND ISNULL(LAG(', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), ') OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), 1) = 0
								THEN 1
								ELSE 0
							END AS StornoWechsel

						INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_6T

						FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_4

					')

					EXEC(@SQL);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepRows = @RowCount, @LogStepError = @Fehler

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
*/
XP130:

					SET @StepPraefix = 'XP130'
					SET @StepText = CONCAT('Datensätze auf Hashbereich', CASE WHEN @ValidToStorno = 1 THEN '- und Storno' ELSE '' END, 'wechsel in Tabelle [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_6] filtern und in [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_7] speichern.')

					SET @SQL = CONCAT('

						SELECT
							SeqID
						,	ChangeSeq
						,	ChangeTyp
						,	ChangeTime
						,	ChangeSource
						,	', REPLACE(@SQL_TableTargetID, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), '
						,	HashID
						,	LastChangeOnDate
						,	HashBereichWechsel
						,	StornoWechsel

						INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_7

						FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_6

						WHERE HashBereichWechsel = 1
						', CASE WHEN @ValidToStorno = 1 THEN CONCAT('AND (', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), ' = 0 OR StornoWechsel = 1)') ELSE '' END

					)

					EXEC(@SQL);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepRows = @RowCount, @LogStepError = @Fehler

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP135:

					SET @StepPraefix = 'XP135'
					SET @StepText = CONCAT('Spalte [SeqID] aus Tabelle [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_7] neu bestimmen und Ergebnis in [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_8] speichern.')

					SET @SQL = CONCAT('

						SELECT
							CAST(ROW_NUMBER() OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY ChangeSeq ASC, ChangeTyp ASC) AS BigInt) AS SeqID
						,	ChangeSeq
						,	ChangeTyp
						,	ChangeTime
						,	ChangeSource
						,	', REPLACE(@SQL_TableTargetID, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), '
						,	HashID
						,	LastChangeOnDate
						,	HashBereichWechsel
						,	StornoWechsel

						INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_8

						FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_7

					')

					EXEC(@SQL);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepRows = @RowCount, @LogStepError = @Fehler

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP140:

					SET @StepPraefix = 'XP140'
					SET @StepText = CONCAT('Spalten [', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), '], [', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), '], [', REPLACE(@SQL_TableTargetDeleteDate, '|x|', ''), '], [', REPLACE(@SQL_TableTargetDeleteFlag, '|x|', ''), '], [', REPLACE(@SQL_TableTargetValidFrom, '|x|', ''), '] und [', REPLACE(@SQL_TableTargetValidTo, '|x|', ''), '] ermitteln und Ergebnis in [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_9_1] speichern.')

					SET @SQL = CONCAT('

						SELECT
							t1.SeqID
						,	t1.ChangeSeq
						,	t1.ChangeTyp
						,	t1.ChangeSource
						,	', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), '
						,	t1.ChangeTime AS ', REPLACE(@SQL_TableTargetValidFrom, '|x|', ''), '
						,	CASE
								WHEN ISNULL(tn.StornoWechsel, 0) = 1 AND ', @ValidToStorno, ' = 1
								AND ISNULL(', REPLACE(@SQL_TableTargetStornoDate, '|x|', 'tn.'), ', DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7)) <= ISNULL(tn.ChangeTime, DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7))
								THEN ISNULL(DATEADD(Second, -1, ', REPLACE(@SQL_TableTargetStornoDate, '|x|', 'tn.'), '), DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7))
								ELSE ISNULL(DATEADD(Second, -1, tn.ChangeTime), DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7))
							END AS ', REPLACE(@SQL_TableTargetValidTo, '|x|', ''), '
						,	CASE
								WHEN ISNULL(tn.ChangeTyp, '''') = ''D''
								THEN 1
								ELSE 0
							END AS ', REPLACE(@SQL_TableTargetDeleteFlag, '|x|', ''), '
						,	CASE
								WHEN ISNULL(tn.ChangeTyp, '''') = ''D''
								THEN ISNULL(tn.ChangeTime, DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7))
								ELSE DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7)
							END AS ', REPLACE(@SQL_TableTargetDeleteDate, '|x|', ''), '
						,	CASE
								WHEN ISNULL(tn.StornoWechsel, 0) = 1 AND ', @ValidToStorno, ' = 1
								THEN 1
								ELSE ', REPLACE(@SQL_TableTargetStornoFlag, '|x|', 't1.'), '
							END AS ', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), '
						,	CASE
								WHEN ISNULL(tn.StornoWechsel, 0) = 1 AND ', @ValidToStorno, ' = 1
								THEN ', REPLACE(@SQL_TableTargetStornoDate, '|x|', 'tn.'), '
								ELSE ', REPLACE(@SQL_TableTargetStornoDate, '|x|', 't1.'), '
							END AS ', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), '
						,	t1.HashID
						,	CASE
								WHEN CAST(t1.ChangeTime AS Date) = ISNULL(CAST(tn.ChangeTime AS Date), DATEFROMPARTS(2099, 12, 31))
								THEN 0
								ELSE 1
							END AS LastChangeOnDate
						,	t1.HashBereichWechsel
						,	t1.StornoWechsel

						INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_9_1

						FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_8 AS t1

						LEFT JOIN ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_8 AS tn -- Nachfolger
						ON	', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), ' = ', REPLACE(@SQL_TableTargetID, '|x|', 'tn.'), '
						AND	t1.SeqID = tn.SeqID - 1

					')

					EXEC(@SQL);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepRows = @RowCount, @LogStepError = @Fehler

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
/*
XP140T:

					SET @StepPraefix = 'XP140T'
					SET @StepText = CONCAT('Spalten [', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), '], [', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), '], [', REPLACE(@SQL_TableTargetDeleteDate, '|x|', ''), '], [', REPLACE(@SQL_TableTargetDeleteFlag, '|x|', ''), '], [', REPLACE(@SQL_TableTargetValidFrom, '|x|', ''), '] und [', REPLACE(@SQL_TableTargetValidTo, '|x|', ''), '] ermitteln und Ergebnis in [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_9_1T] speichern.')

					SET @SQL = CONCAT('

						SELECT
							SeqID
						,	ChangeSeq
						,	ChangeTyp
						,	ChangeSource
						,	', REPLACE(@SQL_TableTargetID, '|x|', ''), '
						,	ChangeTime AS ', REPLACE(@SQL_TableTargetValidFrom, '|x|', ''), '
						,	CASE
								WHEN ISNULL(LEAD(StornoWechsel) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), 0) = 1 AND ', @ValidToStorno, ' = 1
								AND ISNULL(LEAD(', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), ') OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7)) <= ISNULL(LEAD(ChangeTime) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7))
								THEN LEAD(DATEADD(Second, -1, ', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), ')) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC)
								ELSE ISNULL(LEAD(DATEADD(Second, -1, ChangeTime)) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7))
							END AS ', REPLACE(@SQL_TableTargetValidTo, '|x|', ''), '
						,	CASE
								WHEN ISNULL(LEAD(ChangeTyp) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), '''') = ''D''
								THEN 1
								ELSE 0
							END AS ', REPLACE(@SQL_TableTargetDeleteFlag, '|x|', ''), '
						,	CASE
								WHEN ISNULL(LEAD(ChangeTyp) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), '''') = ''D''
								THEN LEAD(ChangeTime) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC)
								ELSE DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7)
							END AS ', REPLACE(@SQL_TableTargetDeleteDate, '|x|', ''), '
						,	CASE
								WHEN ISNULL(LEAD(StornoWechsel) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), 0) = 1 AND ', @ValidToStorno, ' = 1
								THEN 1
								ELSE ', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), '
							END AS ', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), '
						,	CASE
								WHEN ISNULL(LEAD(StornoWechsel) OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC), 0) = 1 AND ', @ValidToStorno, ' = 1
								THEN LEAD(', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), ') OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY SeqID ASC)
								ELSE ', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), '
							END AS ', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), '
						,	HashID
						,	LastChangeOnDate
						,	HashBereichWechsel
						,	StornoWechsel

						INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_9_1T

						FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_7

					')

					EXEC(@SQL);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepRows = @RowCount, @LogStepError = @Fehler

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
*/
XP150:

					SET @StepPraefix = 'XP150'
					SET @StepText = CONCAT('Spalten [SchluesselID], [', REPLACE(@SQL_TableTargetCreateDate, '|x|', ''), '], [', REPLACE(@SQL_TableTargetUpDate, '|x|', ''), '] und [LastChange] ermitteln und Ergebnis in [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_8_2] speichern.')

					SET @SQL = CONCAT('

						SELECT
							ROW_NUMBER() OVER (ORDER BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ') AS SchluesselID
						,	', REPLACE(@SQL_TableTargetID, '|x|', ''), '
						,	MIN(', REPLACE(@SQL_TableTargetValidFrom, '|x|', ''), ') AS ', REPLACE(@SQL_TableTargetCreateDate, '|x|', ''), '
						,	MAX(', REPLACE(@SQL_TableTargetValidFrom, '|x|', ''), ') AS ', REPLACE(@SQL_TableTargetUpDate, '|x|', ''), '
						,	CAST(''',CONVERT(VarChar(27), CAST(@SnapshotTimestampUTC AT TIME ZONE 'UTC' AT TIME ZONE 'Central European Standard Time' AS DateTime2), 126),''' AS DateTime2) AS LastChange
						INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_9_2

						FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_9_1

						GROUP BY ', REPLACE(@SQL_TableTargetID, '|x|', '')

					)

					EXEC(@SQL);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepRows = @RowCount, @LogStepError = @Fehler

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
/*
XP160: -- alter Schritt XP370

					SET @StepPraefix = 'XP160'
					SET @StepText = CONCAT('Tabelle [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_FinalTable] erstellen.')

					SET @SQL = CONCAT('

						SELECT
							IDENTITY(BigInt,1,1) AS RowID
						,	t3.SchluesselID AS SchluesselID
						,	', REPLACE(@SQL_TableTargetID, '|x|', 't1.')

					)

					SET @SQL1 = ISNULL(REPLACE(@SQL_TableTargetDefinition1, '|x|', 't1.'), '')

					SET @SQL2 = ISNULL(REPLACE(@SQL_TableTargetDefinition2, '|x|', 't1.'), '')

					SET @SQL3 = ISNULL(REPLACE(@SQL_TableTargetDefinition3, '|x|', 't1.'), '')

					SET @SQL4 = CONCAT('

						,	RANK() OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), ' ORDER BY ', REPLACE(@SQL_TableTargetValidFrom, '|x|', 't2.'), ' DESC) AS Rang
						,	t2.HashID
						,	CAST(', CASE WHEN @LastChangeOnDate = 1 THEN CONCAT('CAST(', REPLACE(@SQL_TableTargetValidFrom, '|x|', 't2.'), ' AS Date)') ELSE REPLACE(@SQL_TableTargetValidFrom, '|x|', 't2.') END, ' AS DateTime2) AS ', REPLACE(@SQL_TableTargetValidFrom, '|x|', ''), '
						,	CAST(', CASE WHEN @LastChangeOnDate = 1 THEN CONCAT('CAST(DATEADD(Day, -1, ', REPLACE(@SQL_TableTargetValidTo, '|x|', 't2.'), ') AS Date)') ELSE REPLACE(@SQL_TableTargetValidTo, '|x|', 't2.') END, ' AS DateTime2) ', CASE WHEN @LastChangeOnDate = 1 THEN '+ CAST(''23:59:59'' AS DateTime2)' ELSE '' END, ' AS ', REPLACE(@SQL_TableTargetValidTo, '|x|', ''), '
						,	CAST(', CASE WHEN @LastChangeOnDate = 1 THEN CONCAT('CAST(', REPLACE(@SQL_TableTargetCreateDate, '|x|', 't3.'), ' AS Date)') ELSE REPLACE(@SQL_TableTargetCreateDate, '|x|', 't3.') END, ' AS DateTime2) AS ', REPLACE(@SQL_TableTargetCreateDate, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetUpDate, '|x|', 't3.'), '
						,	', REPLACE(@SQL_TableTargetStornoFlag, '|x|', 't2.'), '
						,	CAST(', CASE WHEN @LastChangeOnDate = 1 THEN CONCAT('CAST(', REPLACE(@SQL_TableTargetStornoDate, '|x|', 't2.'), ' AS Date)') ELSE REPLACE(@SQL_TableTargetStornoDate, '|x|', 't2.') END, ' AS DateTime2) AS ', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetDeleteFlag, '|x|', 't2.'), '
						,	CAST(', CASE WHEN @LastChangeOnDate = 1 THEN CONCAT('CAST(', REPLACE(@SQL_TableTargetDeleteDate, '|x|', 't2.'), ' AS Date)') ELSE REPLACE(@SQL_TableTargetDeleteDate, '|x|', 't2.') END, ' AS DateTime2) AS ', REPLACE(@SQL_TableTargetDeleteDate, '|x|', ''), '
						,	t2.LastChangeOnDate
						,	t3.LastChange

						INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_FinalTable

						FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_3 AS t1

						INNER JOIN ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_9_1 AS t2
						ON ', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), ' = ', REPLACE(@SQL_TableTargetID, '|x|', 't2.'), '
						AND t1.ChangeSeq = t2.ChangeSeq
						AND t1.ChangeTyp = t2.ChangeTyp
						AND t2.ChangeTyp IN (''I'', ''U'', ''O'')
						', CASE WHEN @ValidToStorno = 1 THEN 'AND t2.StornoWechsel = 0' ELSE '' END, '

						INNER JOIN ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_9_2 AS t3
						ON ', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), ' = ', REPLACE(@SQL_TableTargetID, '|x|', 't3.'), '

					')

					EXEC(@SQL+@SQL1+@SQL2+@SQL3+@SQL4);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepSQL1 = @SQL1, @LogStepSQL2 = @SQL2, @LogStepSQL3 = @SQL3, @LogStepSQL4 = @SQL4, @LogStepRows = @RowCount, @LogStepError = @Fehler

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''; SET @SQL4=''
*/

XP160:

					SET @StepPraefix = 'XP160'
					SET @StepText = CONCAT('Tabelle [', @SQL_TableTargetString, '_RAW] erstellen.')

					SET @SQL = CONCAT('

						DROP TABLE IF EXISTS ', @SQL_TableTargetString, '_RAW;

						SELECT
							t3.SchluesselID AS SchluesselID
						,	', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), '
						,	', REPLACE(@Fieldlist2, '|x|', 't1.')

					)

					SET @SQL1 = CONCAT('

						,	t2.HashID
						,	', REPLACE(@SQL_TableTargetCreateDate, '|x|', 't3.'), '
						,	', REPLACE(@SQL_TableTargetUpDate, '|x|', 't3.'), '
						,	', REPLACE(@SQL_TableTargetValidFrom, '|x|', 't2.'), '
						,	', REPLACE(@SQL_TableTargetValidTo, '|x|', 't2.'), '
						,	', REPLACE(@SQL_TableTargetStornoFlag, '|x|', 't2.'), '
						,	', REPLACE(@SQL_TableTargetStornoDate, '|x|', 't2.'), '
						,	', REPLACE(@SQL_TableTargetDeleteFlag, '|x|', 't2.'), '
						,	', REPLACE(@SQL_TableTargetDeleteDate, '|x|', 't2.'), '
						,	t2.LastChangeOnDate
						,	t3.LastChange

						INTO ', @SQL_TableTargetString, '_RAW

						FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_3 AS t1

						INNER JOIN ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_9_1 AS t2
						ON ', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), ' = ', REPLACE(@SQL_TableTargetID, '|x|', 't2.'), '
						AND t1.ChangeSeq = t2.ChangeSeq
						AND t1.ChangeTyp = t2.ChangeTyp
						AND t2.ChangeTyp IN (''I'', ''U'', ''O'')
						', CASE WHEN @ValidToStorno = 1 THEN 'AND t2.StornoWechsel = 0' ELSE '' END, '

						INNER JOIN ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_ct_9_2 AS t3
						ON ', REPLACE(@SQL_TableTargetID, '|x|', 't1.'), ' = ', REPLACE(@SQL_TableTargetID, '|x|', 't3.'), '

					')

					EXEC(@SQL+@SQL1);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepSQL1 = @SQL1, @LogStepRows = @RowCount, @LogStepError = @Fehler

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''; SET @SQL4=''

XP170:

					SET @StepPraefix = 'XP170'
					SET @StepText = CONCAT('Tabelle [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_FinalTable] erstellen.')

					SET @SQL = CONCAT('

						SELECT
							IDENTITY(BigInt,1,1) AS RowID
						,	SchluesselID
						,	', REPLACE(@SQL_TableTargetID, '|x|', '')

					)

					SET @SQL1 = ISNULL(REPLACE(@SQL_TableTargetDefinition1, '|x|', ''), '')

					SET @SQL2 = ISNULL(REPLACE(@SQL_TableTargetDefinition2, '|x|', ''), '')

					SET @SQL3 = ISNULL(REPLACE(@SQL_TableTargetDefinition3, '|x|', ''), '')

					SET @SQL4 = CONCAT('

						,	RANK() OVER (PARTITION BY ', REPLACE(@SQL_TableTargetID, '|x|', ''), ' ORDER BY ', REPLACE(@SQL_TableTargetValidFrom, '|x|', ''), ' DESC) AS Rang
						,	HashID
						,	CAST(', CASE WHEN @LastChangeOnDate = 1 THEN CONCAT('CAST(', REPLACE(@SQL_TableTargetValidFrom, '|x|', ''), ' AS Date)') ELSE REPLACE(@SQL_TableTargetValidFrom, '|x|', '') END, ' AS DateTime2) AS ', REPLACE(@SQL_TableTargetValidFrom, '|x|', ''), '
						,	', CASE WHEN @LastChangeOnDate = 1
                                    THEN CONCAT('DATEADD(Second, 86399, CAST(CAST(DATEADD(Day, -1, ', REPLACE(@SQL_TableTargetValidTo, '|x|', ''), ') AS Date) AS DateTime2))')  -- 86399 sekunden sind 23h 59min 59 sec, DATEADD hat als Rückgabe den Datentyp des 3. Paramerters => Zwei Cast
                                    ELSE CONCAT('CAST(', REPLACE(@SQL_TableTargetValidTo, '|x|', ''), ' AS DateTime2)')
                               END, ' AS ', REPLACE(@SQL_TableTargetValidTo, '|x|', ''), '
						,	CAST(', CASE WHEN @LastChangeOnDate = 1 THEN CONCAT('CAST(', REPLACE(@SQL_TableTargetCreateDate, '|x|', ''), ' AS Date)') ELSE REPLACE(@SQL_TableTargetCreateDate, '|x|', '') END, ' AS DateTime2) AS ', REPLACE(@SQL_TableTargetCreateDate, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetUpDate, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetStornoFlag, '|x|', ''), '
						,	CAST(', CASE WHEN @LastChangeOnDate = 1 THEN CONCAT('CAST(', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), ' AS Date)') ELSE REPLACE(@SQL_TableTargetStornoDate, '|x|', '') END, ' AS DateTime2) AS ', REPLACE(@SQL_TableTargetStornoDate, '|x|', ''), '
						,	', REPLACE(@SQL_TableTargetDeleteFlag, '|x|', ''), '
						,	CAST(', CASE WHEN @LastChangeOnDate = 1 THEN CONCAT('CAST(', REPLACE(@SQL_TableTargetDeleteDate, '|x|', ''), ' AS Date)') ELSE REPLACE(@SQL_TableTargetDeleteDate, '|x|', '') END, ' AS DateTime2) AS ', REPLACE(@SQL_TableTargetDeleteDate, '|x|', ''), '
						,	LastChangeOnDate
						,	LastChange

						INTO ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '_FinalTable

						FROM ', @SQL_TableTargetString, '_RAW

					')

					EXEC(@SQL+@SQL1+@SQL2+@SQL3+@SQL4);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepSQL1 = @SQL1, @LogStepSQL2 = @SQL2, @LogStepSQL3 = @SQL3, @LogStepSQL4 = @SQL4, @LogStepRows = @RowCount, @LogStepError = @Fehler

					IF @Fehler > 0
						GoTo Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''; SET @SQL4=''

				END -- @Historisierung = 1

		if @Fehler is null or @Fehler=0 
			Begin
XP380:
				SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
				SET @StepText=  Concat('','Tabelle [',@SQL_TableTargetString,'] in [',@SQL_TableTargetString,'_BACKUP] speichern und [',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,'_VIEW] auf Backup umsteuern.')
				SET @SQL=concat('Use ',@SQL_TableTargetDB,';
					
							If OBJECT_ID(''',@SQL_TableTargetString, ''', ''U'') IS NOT NULL 
								Begin
									EXEC(''CREATE or ALTER VIEW ',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,'_VIEW AS Select * from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'_FinalTable where ',Replace(@SQL_TableTargetValidFrom,'|x|',''),'<=',Replace(@SQL_TableTargetValidTo,'|x|',''),''')
									drop table if exists ',@SQL_TableTargetString,'_BACKUP;
									EXEC sp_rename ''',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,''',''',@SQL_TableTargetName,'_BACKUP'';
									EXEC(''CREATE or ALTER VIEW ',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,'_VIEW AS Select * from ',@SQL_TableTargetString,'_BACKUP where ',Replace(@SQL_TableTargetValidFrom,'|x|',''),'<=',Replace(@SQL_TableTargetValidTo,'|x|',''),''')
								end 
							EXEC sp_rename ''',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,'_TEMP',@TEMPPraefix,'_FinalTable'',''',@SQL_TableTargetName,''';
							EXEC(''CREATE or ALTER VIEW ',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,'_VIEW AS Select * from ',@SQL_TableTargetString,' where ',Replace(@SQL_TableTargetValidFrom,'|x|',''),'<=',Replace(@SQL_TableTargetValidTo,'|x|',''),''')
							')
				EXEC(@SQL+@SQL1+@SQL2);
				SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
				EXEC #LogStep @LogID=@LogID, @LogStep='XP380', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

				if @Fehler>0
					goto Fehlermarke
			end

		if @Fehler>0 
			goto Fehlermarke

		SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP390:
			If @InsertInto=0
				Begin 
					SET @StepText=  Concat('Index [x', replace(@SQL_TableTargetID,'|x|',''),'] in Zieltabelle [',@SQL_TableTargetString,'] anlegen.')			
					SET @SQL=Concat('Use ',@SQL_TableTargetDB,';

					CREATE NONCLUSTERED INDEX x', replace(@SQL_TableTargetID,'|x|',''), ' ON ',@SQL_TableTargetString,'
					(
						SchluesselID ASC,
						',Replace(@SQL_TableTargetID,'|x|',''), ' ASC,
						',Replace(@SQL_TableTargetValidFrom,'|x|',''),' ASC
					) ;

					CREATE CLUSTERED INDEX xRowID ON ',@SQL_TableTargetString,' (RowID ASC) 
					')

					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='XP390', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke
				
					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
				End

XP400:
			SET @StepText=  Concat('','Zeilenanzahl der Tabelle [', @SQL_TableTargetString, '] aus SYS-Tabellen ermitteln.')
			SET @SQL=Concat('SELECT @Zeilenanzahl =(SELECT max(rows) as rowcnt 
								FROM ',@SQL_TableTargetDB,'.sys.partitions WHERE object_id=OBJECT_ID(''', @SQL_TableTargetString, ''', ''U''))')
	
			EXEC sp_EXECutesql @SQL, N'@Zeilenanzahl bigint OUT', @Zeilenanzahl OUT;
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep='XP400', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke

			SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
XP410:
			SET @StepText=  Concat('','Die geänderten Datensätze der letzten ',@DeltaDays,' Tag(e) aus Tabelle [',@SQL_TableTargetString,'] in [',@SQL_TableTargetString,'_DELTA] speichern.')
			SET @SQL= CONCAT('Use ',@SQL_TableTargetDB,';
							 Drop table if exists ',@SQL_TableTargetString,'_DELTA;

							 Select t1.* 
							 into ',@SQL_TableTargetString,'_DELTA
							 from ',@SQL_TableTargetString,' t1
							 where ', replace(@SQL_TableTargetUpDate,'|x|',''), ' >= cast(dateadd(d,-',@DeltaDays,',cast(Getdate() as date)) as DateTime2)

							');

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep='XP410', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke

			SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

		END -- IF Ladeverfahren = F

XP420:
	 if left(@Ladeverfahren,1) in ('D')
		begin
			if @Historisierung=2 or OBJECT_ID(Concat(@SQL_TableSourceString, @Praefix), 'U') IS NULL 
				begin
					SET @StepText=  Concat('','Tabelle [',@SQL_TableSourceString,'] in Tabelle [', @SQL_TableTargetString, '_RAW] speichern.')
					SET @SQL= Concat('drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,';
									 Select distinct
										',Replace(@SQL_TableSourceID,'|x|','t1.'),' as ',Replace(@SQL_TableTargetID,'|x|',''),'
										,',Replace(Replace(@Fieldlist1,'|x|','t1.'),'|xx|',''), '
										,cast(HASHBYTES(''SHA1'', (select ', Replace(@Fieldlist2,'|x|','t1.') ,' FOR XML RAW)) as varbinary(100)) as HashID
										,', Replace(@SQL_TableSourceCreateDate,'|x|','t1.'),' as ',Replace(@SQL_TableTargetValidFrom,	'|x|',''),'
										, DateTime2FromParts(2099, 12, 31, 23, 59, 59 ,00 ,7)  as ',Replace(@SQL_TableTargetValidTo,		'|x|',''),'
										,', Replace(@SQL_TableSourceCreateDate,'|x|','t1.'),' as ',Replace(@SQL_TableTargetCreateDate,	'|x|',''),'
										,', Replace(@SQL_TableSourceUpDate,'|x|','t1.'),'	  as ',Replace(@SQL_TableTargetUpDate,		'|x|',''),' 
										,', Replace(@SQL_TableSourceStornoFlag,'|x|','t1.'),' as ',Replace(@SQL_TableTargetStornoFlag,	'|x|',''),' 
										,', Replace(@SQL_TableSourceStornoDate,'|x|','t1.'),' as ',Replace(@SQL_TableTargetStornoDate,	'|x|',''),' 
										,0													  as ',Replace(@SQL_TableTargetDeleteFlag,	'|x|',''),'
										, DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7)  as ',Replace(@SQL_TableTargetDeleteDate,	'|x|',''),'
										,1 as LastChangeOnDate
									into  ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'
									from ',@SQL_TableSourceString,' t1
									 ', Replace(@SQL_TableSource_Join, '|x|','t1.'), '
									',case when len(@SQL_TableSource_Where)>0 then concat(' where ', Replace(@SQL_TableSource_Where,'|x|','t1.'),' and ') else ' where ' end  ,'
									cast(', Replace(@SQL_TableSourceUpDate,'|x|','t1.'),' as date)>=dateadd(d,-',@DELAY,',cast(getdate() as date)) 
									');

					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='XP420', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
				end
			else
				begin

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
					SET @TestLoop='';
					SET @Praefix='__ct';
					Print '***************************************'
					Print @SQL_TableSourceString + @Praefix
					IF OBJECT_ID(Concat(@SQL_TableSourceString, @Praefix), 'U') IS NOT NULL 
						Begin
XP430:
							SET @StepText = Concat('Relevante Änderungen aus [', @SQL_TableSourceString, @Praefix, '] extrahieren und in [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '] speichern. (Änderungen ab: ', @LastProcessedChangeLocal, ' CEST)')
							SET @SQL= Concat('drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,';

											  Select 
												 CAST(0 AS BigInt) AS SchluesselID
												,header__change_oper				as ChangeTyp
												,header__change_seq					as ChangeID
												,', Replace(@SQL_TableSourceID,'|x|','t1.'),' as ', replace(@SQL_TableTargetID,'|x|',''), '
												,', Replace(@Fieldlist2,'|x|','t1.'), '
												,HASHBYTES(''SHA1'', (select ', Replace(@Fieldlist2,'|x|','t1.') ,' FOR XML RAW)) as HashID
												,cast([header__timestamp] AT TIME ZONE ''UTC'' AT TIME ZONE ''Central European Standard Time'' as DateTime2) as ',Replace(@SQL_TableTargetValidFrom,'|x|',''),'
						  						,case when header__change_oper=''D'' then 1 else 0 end ',Replace(@SQL_TableTargetDeleteFlag,'|x|',''),'
												,case when header__change_oper=''D''
													then cast([header__timestamp] AT TIME ZONE ''UTC'' AT TIME ZONE ''Central European Standard Time'' as DateTime2)
													else Null end ',Replace(@SQL_TableTargetDeleteDate,'|x|',''),'
												,', replace(@SQL_TableSourceCreateDate,'|x|','t1.'), ' as ', replace(@SQL_TableTargetCreateDate,'|x|',''), '
												,cast([header__timestamp] AT TIME ZONE ''UTC'' AT TIME ZONE ''Central European Standard Time'' as DateTime2) as ', replace(@SQL_TableTargetUpDate,'|x|',''), '
												,', Replace(@SQL_TableSourceStornoFlag, '|x|','t1.'), ' as ', Replace(@SQL_TableTargetStornoFlag,	'|x|',''), '
												,', Replace(@SQL_TableSourceStornoDate, '|x|','t1.'), ' as ', Replace(@SQL_TableTargetStornoDate,	'|x|',''), '
												,SYSUTCDATETIME() AS Timestamp
												,CAST(SYSUTCDATETIME() AT TIME ZONE ''UTC'' AT TIME ZONE ''Central European Standard Time'' AS DateTime2) AS LastChange
											   into ', @SQL_TableTargetString,'_TEMP',@TEMPPraefix,'
											   ')

							SET @SQL1= Concat('	from ', @SQL_TableSourceString,@Praefix,' t1
											   ', Replace(@SQL_TableSource_Join, '|x|','t1.'), '
											   where header__change_oper in (''U'',''I'',''D'')
													AND [header__timestamp] > CAST(''', CONVERT(nVarChar, CAST(@LastProcessedChangeLocal AT TIME ZONE 'Central European Standard Time' AT TIME ZONE 'UTC' AS DateTime2), 126), ''' AS DateTime2)',
													case when len(@SQL_TableSource_Where)>0 then concat(' and ', Replace(@SQL_TableSource_Where,'|x|','t1.')) else '' end
												)

							EXEC(@SQL+@SQL1+@SQL2);
							SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
							EXEC #LogStep @LogID=@LogID, @LogStep='XP430', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

							if @Fehler>0
								goto Fehlermarke

							SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP431:

							SET @StepPraefix = 'XP431'
							SET @StepText = CONCAT('Zeitstempel der Daten aus [', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, '] in Variable speichern.')

							SET @SQL = CONCAT('SELECT @SnapshotTimestamp = (SELECT TOP 1 Timestamp AS SnapshotTimestamp FROM ', @SQL_TableTargetString, '_TEMP', @TEMPPraefix, ')')

							EXEC sp_EXECutesql @SQL, N'@SnapshotTimestamp DateTime2 OUT', @SnapshotTimestampUTC OUT;
							SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT

							EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepRows = @RowCount, @LogStepError = @Fehler, @LogTableTime = @SnapshotTimestampUTC

							IF @Fehler > 0
								GoTo Fehlermarke

							SET @SQL = ''

XP435:

							SET @StepPraefix = 'XP435'
							SET @StepText = CONCAT('Zeitstempel vom letzten verarbeiteten Eintrag aus [', @SQL_TableTargetString,'_TEMP',@TEMPPraefix, '] in @TableCTLastUpdateLocal speichern.')

							SET @SQL =	CONCAT('SELECT @TableCTLastUpdateLocal = (
													SELECT MAX(', REPLACE(@SQL_TableTargetUpDate, '|x|', ''), ') AS Zeitstempel
													FROM ', @SQL_TableTargetString,'_TEMP',@TEMPPraefix, '
												);'
										)

							EXEC sp_EXECutesql @SQL, N'@TableCTLastUpdateLocal DateTime2 OUT', @TableCTLastUpdateLocal OUT;
							SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT

							EXEC #LogStep @LogID = @LogID, @LogStep = @StepPraefix, @LogStepText = @StepText, @LogStepSQL = @SQL, @LogStepRows = @RowCount, @LogStepError = @Fehler, @LogTableTime = @TableCTLastUpdateLocal

							IF @Fehler > 0
								GoTo Fehlermarke

							SET @SQL = ''

						End
				end

XP440:
			SET @StepText=  Concat('','Tabelle [',@SQL_TableTargetString,'_DELTA] in [',@SQL_TableTargetString,'_DELTA_BACKUP] speichern und [',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,'_DELTA_VIEW] auf Backup umsteuern.')
			SET @SQL= CONCAT('Use ',@SQL_TableTargetDB,';
								drop table if exists ',@SQL_TableTargetString,'_DELTA_BACKUP;')
			EXEC(@SQL);
			SET @SQL =Concat('Use ',@SQL_TableTargetDB,';

							  Select *
							  into ',@SQL_TableTargetString,'_DELTA_BACKUP
							  from ',@SQL_TableTargetString,'_DELTA

							  EXEC(''CREATE or ALTER VIEW ',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,'_DELTA_VIEW AS Select * from ',@SQL_TableTargetString,'_DELTA_BACKUP'')');
			
			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep='XP440', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke

			SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

			IF OBJECT_ID(@SQL_TableSourceString, 'U') IS NOT NULL 
				Begin
XP450:
					SET @StepText= CONCAT('Daten aus der [', @SQL_TableTargetString,'_RAW] laden und in [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'] speichern!')
					SET @SQL= Concat('Insert into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'  
									  Select     t1.SchluesselID
												,''R'' as ChangeTyp
												,',Replace(@SQL_TableTargetID,'|x|','t1.'),' as ChangeID
												,',Replace(@SQL_TableTargetID,'|x|','t1.'),' 
												,',Replace(@Fieldlist2,'|x|','t1.'),'
												,t1.HashID
												,',Replace(@SQL_TableTargetValidFrom,'|x|','t1.'),'
									  			,',Replace(@SQL_TableTargetDeleteFlag,'|x|','t1.'),'
												,isnull(',Replace(@SQL_TableTargetDeleteDate,'|x|','t1.'),' , DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7)) as ',Replace(@SQL_TableTargetDeleteDate,'|x|',''),'
												,', replace(@SQL_TableTargetCreateDate,'|x|',''), '
												,', replace(@SQL_TableTargetUpDate,'|x|',''), '
												,', replace(@SQL_TableTargetStornoFlag,'|x|',''), '
												,', replace(@SQL_TableTargetStornoDate,'|x|',''), '
												,''', CONVERT(nVarChar, @SnapshotTimestampUTC, 126), '''
												,t1.LastChange
									  from ', @SQL_TableTargetString,'_RAW t1
										join (Select Distinct ',Replace(@SQL_TableTargetID,'|x|',''),' from ', @SQL_TableTargetString,'_TEMP',@TEMPPraefix,') t2 on ', Replace(@SQL_TableTargetID,'|x|','t1.'), ' = ', Replace(@SQL_TableTargetID,'|x|','t2.'),'
									 ')
					
					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='XP450', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP460:
					SET @StepText=  concat('Daten aus der Tabelle [', @SQL_TableTargetString,'_RAW] löschen!')
					SET @SQL= Concat('Delete ', @SQL_TableTargetString,'_RAW
									  from ', @SQL_TableTargetString,'_RAW t1
										join (Select Distinct ',Replace(@SQL_TableTargetID,'|x|',''),' from ', @SQL_TableTargetString,'_TEMP',@TEMPPraefix,') t2 on ', Replace(@SQL_TableTargetID,'|x|','t1.'), ' = ', Replace(@SQL_TableTargetID,'|x|','t2.'),'
									 ')
					
					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='XP460', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP470:
					SET @StepText=  concat('Daten aus der Tabelle [', @SQL_TableTargetString,'] löschen!')
					SET @SQL= Concat('									
									  Delete ', @SQL_TableTargetString,'
									  from ', @SQL_TableTargetString,' t1
										join (Select Distinct ',Replace(@SQL_TableTargetID,'|x|',''),' from ', @SQL_TableTargetString,'_TEMP',@TEMPPraefix,') t2 on ', Replace(@SQL_TableTargetID,'|x|','t1.'), ' = ', Replace(@SQL_TableTargetID,'|x|','t2.'),'
									 ')
					
					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='XP470', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP480:
					SET @StepText= concat('Daten aus der Tabelle [', @SQL_TableTargetString,'_DELTA] löschen!')
					SET @SQL= Concat('
									  Delete ', @SQL_TableTargetString,'_DELTA
									  from ', @SQL_TableTargetString,'_DELTA t1
										join (Select Distinct ',Replace(@SQL_TableTargetID,'|x|',''),' from ', @SQL_TableTargetString,'_TEMP',@TEMPPraefix,') t2 on ', Replace(@SQL_TableTargetID,'|x|','t1.'), ' = ', Replace(@SQL_TableTargetID,'|x|','t2.'),'
									 ')
					
					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='XP480', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP490:
					SET @StepText=  concat('Daten, die älter sind, als ',dateadd(d,-@DeltaDays,cast(Getdate() as date)),' aus der Tabelle [', @SQL_TableTargetString,'Delta] löschen!')
					SET @SQL= Concat('
									  --> Alte Daten in der Tabelle []_Delta löschen
									  Delete ', @SQL_TableTargetString,'_DELTA
									  from ', @SQL_TableTargetString,'_DELTA t1
										join (Select ',Replace(@SQL_TableTargetID,'|x|',''),'
											  ,Max(',Replace(@SQL_TableTargetValidFrom,'|x|',''),') as max_',Replace(@SQL_TableTargetValidFrom,'|x|',''),'
											  from ', @SQL_TableTargetString,'_DELTA
											  group by ',Replace(@SQL_TableTargetID,'|x|',''),'
											  having Max(',Replace(@SQL_TableTargetValidFrom,'|x|',''),') < cast(dateadd(d,-',@DeltaDays,',cast(Getdate() as date)) as DateTime2)
											  ) t2 on ', Replace(@SQL_TableTargetID,'|x|','t1.'), ' = ', Replace(@SQL_TableTargetID,'|x|','t2.'),'
									')

					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='XP490', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP500:
					SET @StepText=  concat('Daten aus Tabelle [', @SQL_TableTargetString,'_TEMP',@TEMPPraefix,'] aufbereiten und in Tabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'1] speichern!')
					SET @SQL= Concat('
									  drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'1;

									  Select     t1.SchluesselID
												,',Replace(@SQL_TableTargetID,'|x|','t1.'),' 
												,',Replace(@Fieldlist2,'|x|','t1.'),'
												,t1.HashID
												,case when t4.Loeschdatensatz_ist_alleine=1 
													  then ', replace(@SQL_TableTargetCreateDate,'|x|','t1.'), ' 
													  else ',Replace(@SQL_TableTargetValidFrom,'|x|','t1.'),' end as ',Replace(@SQL_TableTargetValidFrom,'|x|',''),'
									  			,isnull(',Replace(@SQL_TableTargetDeleteFlag,'|x|','t3.'),',0) as ',Replace(@SQL_TableTargetDeleteFlag,'|x|',''),'
												,isnull(',Replace(@SQL_TableTargetDeleteDate,'|x|','t3.'),' ,DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7)) as ',Replace(@SQL_TableTargetDeleteDate,'|x|',''),'
												,', replace(@SQL_TableTargetCreateDate,'|x|',''), '
												,', replace(@SQL_TableTargetUpDate,'|x|',''), '
												,isnull(',replace(@SQL_TableTargetStornoFlag,'|x|',''),',0) as ',replace(@SQL_TableTargetStornoFlag,'|x|',''),'
												,', replace(@SQL_TableTargetStornoDate,'|x|',''), '
												,t1.LastChange
									  into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'1  
									  from ', @SQL_TableTargetString,'_TEMP',@TEMPPraefix,' t1
										join (Select ',Replace(@SQL_TableTargetID,'|x|',''),', max(',Replace(@SQL_TableTargetValidFrom,'|x|',''),') as max_',Replace(@SQL_TableTargetValidFrom,'|x|',''),' 
											  from ', @SQL_TableTargetString,'_TEMP',@TEMPPraefix,'
											  group by ',Replace(@SQL_TableTargetID,'|x|',''),'
											  ) t2 on ', Replace(@SQL_TableTargetID,'|x|','t1.'), ' = ', Replace(@SQL_TableTargetID,'|x|','t2.'),'
										left join (Select ',Replace(@SQL_TableTargetID,'|x|','t1.'),', 1 as ',Replace(@SQL_TableTargetDeleteFlag,'|x|',''),', max(',Replace(@SQL_TableTargetValidFrom,'|x|','t1.'),') as ',Replace(@SQL_TableTargetDeleteDate,'|x|',''),' 
												   from ', @SQL_TableTargetString, '_TEMP',@TEMPPraefix,' t1
														left join ', @SQL_TableTargetString, '_TEMP',@TEMPPraefix,' t2 on ',Replace(@SQL_TableTargetID,'|x|','t1.'),'=',Replace(@SQL_TableTargetID,'|x|','t2.'),'  
																									and ', replace(@SQL_TableTargetUpDate,'|x|','t1.'), '<=', replace(@SQL_TableTargetUpDate,'|x|','t2.'), '
																									and t2.ChangeTyp=''I''
												   where t1.ChangeTyp=''D'' and t2.ChangeTyp is null
												   group by ',Replace(@SQL_TableTargetID,'|x|','t1.'),') t3 on ',Replace(@SQL_TableTargetID,'|x|','t1.'),'=',Replace(@SQL_TableTargetID,'|x|','t3.'),' 
										left join (Select ',Replace(@SQL_TableTargetID,'|x|',''),', 1 as Loeschdatensatz_ist_alleine 
												   from ', @SQL_TableTargetString, '_TEMP',@TEMPPraefix,' 
												   group by ',Replace(@SQL_TableTargetID,'|x|',''),'
												   having Count(distinct ChangeTyp)=1) t4 on ',Replace(@SQL_TableTargetID,'|x|','t3.'),'=',Replace(@SQL_TableTargetID,'|x|','t4.'),' 
									  where (t1.ChangeTyp<>''D'' or (t1.ChangeTyp=''D'' and t4.Loeschdatensatz_ist_alleine=1))
									  ',case when @Historisierung=0 then concat(' and t2.max_',Replace(@SQL_TableTargetValidFrom,'|x|',''),'=',Replace(@SQL_TableTargetValidFrom,'|x|','t1.')) else '' end,'
									')

					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='XP500', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
XP510:
					SET @StepText=  concat('Daten aus Tabelle [', @SQL_TableTargetString,'_TEMP',@TEMPPraefix,'1] aufbereiten und in Tabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'2] speichern!')
					SET @SQL2= Concat('
					                  drop table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'2;
									  
									  Select Distinct
												 t1.SchluesselID
												,',Replace(@SQL_TableTargetID,'|x|','t1.'),' 
												,',Replace(@Fieldlist2,'|x|','t1.'),'
												,t1.HashID
												,',Replace(@SQL_TableTargetCreateDate,	'|x|','t1.'),'
												,',Replace(@SQL_TableTargetUpDate,		'|x|','t1.'),'
												,',Replace(@SQL_TableTargetValidFrom,	'|x|','t1.'),'
												,isnull(dateadd(s,-1,lead(',Replace(@SQL_TableTargetValidFrom,'|x|','t1.'),') over (partition by ',Replace(@SQL_TableTargetID,'|x|','t1.'),' order by ',Replace(@SQL_TableTargetValidFrom,'|x|','t1.'),')), DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7)) as ',Replace(@SQL_TableTargetValidTo,'|x|',''),'
												,',Replace(@SQL_TableTargetStornoFlag,	'|x|','t1.'),'
												,',Replace(@SQL_TableTargetStornoDate,	'|x|','t1.'),'
									  			,',Replace(@SQL_TableTargetDeleteFlag,	'|x|','t1.'),'
												,isnull(',Replace(@SQL_TableTargetDeleteDate,'|x|','t1.'),' , DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7)) as ',Replace(@SQL_TableTargetDeleteDate,'|x|',''),'
												,case when ',Replace(@SQL_TableTargetValidFrom,'|x|','t1.'),'=',Replace(@SQL_TableTargetValidFrom,'|x|','t2.'),' then 1 else 0 end LastChangeOnDate
												,t1.LastChange
									  into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'2
									  from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'1 t1
										outer apply (
													select	top (1) 
															', Replace(@SQL_TableTargetID,			'|x|',''),'
															,',Replace(@SQL_TableTargetValidFrom,	'|x|',''),'
													from	',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'1
													where	',Replace(@SQL_TableTargetID,'|x|',''), '=', Replace(@SQL_TableTargetID,'|x|','t1.'), ' 
														and  DATEADD(DAY, DATEDIFF(DAY, 0,',Replace(@SQL_TableTargetValidFrom,'|x|',''),'),0) = DATEADD(DAY, DATEDIFF(DAY, 0,',Replace(@SQL_TableTargetValidFrom,'|x|','t1.'),'),0) 
													order by ',Replace(@SQL_TableTargetValidFrom,'|x|',''),' DESC
												) t2	;
									')

					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='XP510', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
XP520:
					SET @StepText=  concat('Daten aus Tabelle [', @SQL_TableTargetString,'_TEMP',@TEMPPraefix,'2] in Tabelle [',@SQL_TableTargetString,'_RAW] speichern!')
					SET @SQL2= Concat('
										Insert into ',@SQL_TableTargetString,'_RAW  
										Select * from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'2
										where ',Replace(@SQL_TableTargetValidFrom,'|x|',''),'<',Replace(@SQL_TableTargetValidTo,'|x|',''),'
									') ;
			
					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='XP520', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

					if @Fehler>0
						goto Fehlermarke

					SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
				End
XP530:
			SET @StepText=  Concat('HashBereiche bilden und in [', @SQL_TableTargetString, '_TEMP',@TEMPPraefix,'2_hist] speichern.')		
			SET @SQL=Concat('
			Drop Table if exists ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'2_hist

			Select ', replace(@SQL_TableTargetID,'|x|',''),',Hash_Bereich
				,min(',Replace(@SQL_TableTargetValidFrom,'|x|',''),') as ',Replace(@SQL_TableTargetValidFrom,'|x|',''),'
				,max(LastChangeOnDate) as LastChangeOnDate
				,min(',Replace(@SQL_TableTargetCreateDate,'|x|',''),') as ',Replace(@SQL_TableTargetCreateDate,'|x|',''),'
				,min(',Replace(@SQL_TableTargetUpDate,'|x|',''),') as ',Replace(@SQL_TableTargetUpDate,'|x|',''),'
			into ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'2_hist
			from (
				Select ', replace(@SQL_TableTargetID,'|x|',''),',',Replace(@SQL_TableTargetValidFrom,'|x|',''),',',Replace(@SQL_TableTargetCreateDate,'|x|',''),',',Replace(@SQL_TableTargetUpDate,'|x|',''),'
				,sum(Hash_Bereich_Anfang) over (partition by ', replace(@SQL_TableTargetID,'|x|',''),' order by ',Replace(@SQL_TableTargetValidFrom,'|x|',''),' ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as Hash_Bereich
				,LastChangeOnDate
				from (
					Select ', replace(@SQL_TableTargetID,'|x|',''),',',Replace(@SQL_TableTargetValidFrom,'|x|',''),',',Replace(@SQL_TableTargetCreateDate,'|x|',''),',',Replace(@SQL_TableTargetUpDate,'|x|',''),',LastChangeOnDate
						,case when HashID<>isnull(lag(HashID)  over (partition by ', replace(@SQL_TableTargetID,'|x|',''),' order by ',Replace(@SQL_TableTargetValidFrom,'|x|',''),'),1) then 1 else 0 end Hash_Bereich_Anfang
					from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'2
					',case when @LastChangeOnDate=1 then ' where LastChangeOnDate=1' else '' end,'
					) t1
					) t2
			Group by ', replace(@SQL_TableTargetID,'|x|',''),',Hash_Bereich
			')

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep='XP530', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke
				
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP535:
		
			SET @StepText=  Concat('SchluesselID bilden und in [', @SQL_TableTargetString, '_TEMP',@TEMPPraefix,'_SchluesselID] speichern.')		
			SET @SQL=Concat('

			Declare @MaxSchluesselID as bigint
			SET @MaxSchluesselID=(Select isnull(max(SchluesselID),0) from ',@SQL_TableTargetString,')

			Drop Table if exists ', @SQL_TableTargetString, '_TEMP',@TEMPPraefix,'_SchluesselID

			Select ',Replace(@SQL_TableTargetID,'|x|',''),'
				,cast(Row_Number() over (order by ',Replace(@SQL_TableTargetID,'|x|',''),') as bigint) + @MaxSchluesselID as SchluesselID
			into ', @SQL_TableTargetString, '_TEMP',@TEMPPraefix,'_SchluesselID
			from (Select distinct ',Replace(@SQL_TableTargetID,'|x|',''),' from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'2) t
			')

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep='XP535', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke
				
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

XP540:
			SET @StepText=  Concat('','Tabelle [',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'2] in [',@SQL_TableTargetString,'] speichern.')
			SET @SQL=Concat('SET IDENTITY_INSERT ',@SQL_TableTargetString,' OFF

							 Insert into ',@SQL_TableTargetString,'
							 Select t98.SchluesselID,
									',Replace(@SQL_TableTargetID,'|x|','t1.'),'
								    ',Replace(@SQL_TableTargetDefinition1,'|x|','t1.'))
			SET @SQL1=isnull(Replace(@SQL_TableTargetDefinition2,'|x|','t1.'),'')
			SET @SQL2=isnull(Replace(@SQL_TableTargetDefinition3,'|x|','t1.'),'')
			SET @SQL3=Concat('
								,Rank() over (partition by ',Replace(@SQL_TableTargetID,'|x|','t1.'),' order by ',Replace(@SQL_TableTargetValidFrom,'|x|','t1.'),' DESC) as Rang
								,t1.HashID
								,cast(cast(',Replace(@SQL_TableTargetValidFrom,'|x|',case when @Historisierung>0 then 't99.' else 't1.' end),' as ',case when @LastChangeOnDate=1 then 'date) as DateTime2)' else 'DateTime2) as DateTime2)' end,' as ',Replace(@SQL_TableTargetValidFrom,'|x|',''),'
								,isnull(dateadd(s,-1,lead(cast(cast(',Replace(@SQL_TableTargetValidFrom,'|x|','t1.'),' as ',case when @LastChangeOnDate=1 then 'date) as DateTime2)' else 'DateTime2) as DateTime2)' end,') over (partition by ',Replace(@SQL_TableTargetID,'|x|','t1.'),' order by ',Replace(@SQL_TableTargetValidFrom,'|x|','t1.'),')),
										case when ',Replace(@SQL_TableTargetDeleteFlag,'|x|','t1.'),'=1 then DATEADD(Second,-1,cast(cast(',Replace(@SQL_TableTargetDeleteDate,'|x|','t1.'),' as ',case when @LastChangeOnDate=1 then 'date) as DateTime2)' else 'DateTime2) as DateTime2)' end,' )
												when ',@ValidToStorno,'=1 then ', CASE WHEN @LastChangeOnDate=1
												                                        THEN CONCAT('DATEADD(Second, 86399, CAST(CAST(', Replace(@SQL_TableTargetStornoDate,'|x|','t1.'),' AS Date) as DateTime2))')
												                                        ELSE CONCAT('CAST(', Replace(@SQL_TableTargetStornoDate, '|x|' , 't1.'),' as DateTime2)')
                                                                                   END,'
												else DateTime2FromParts(2099, 12, 31, 23, 59, 59, 00, 7)
												end
										) as ',Replace(@SQL_TableTargetValidTo,'|x|',''),'
								,cast(cast(',Replace(@SQL_TableTargetCreateDate	,'|x|',case when @Historisierung>0 then 't99.' else 't1.' end),' as ',case when @LastChangeOnDate=1 then 'date) as DateTime2)' else 'DateTime2) as DateTime2)' end,' as ',Replace(@SQL_TableTargetCreateDate,'|x|',''),'
								,', Replace(@SQL_TableTargetUpDate				,'|x|',case when @Historisierung>0 then 't99.' else 't1.' end),'
								,', Replace(@SQL_TableTargetStornoFlag			,'|x|','t1.'),'
								,', CASE WHEN @LastChangeOnDate=1
								        THEN CONCAT('DATEADD(Second, 86399, CAST(CAST(', REPLACE(@SQL_TableTargetStornoDate, '|x|', 't1.'), ' AS Date) AS DateTime2))')
								        ELSE CONCAT('CAST(',Replace(@SQL_TableTargetStornoDate	,'|x|','t1.'),' as DateTime2)')
								    end,' as ',Replace(@SQL_TableTargetStornoDate,'|x|',''),'
								,', Replace(@SQL_TableTargetDeleteFlag			,'|x|','t1.'),'
								,', CASE WHEN @LastChangeOnDate=1
								        THEN CONCAT('DATEADD(Second, 86399, CAST(CAST(', REPLACE(@SQL_TableTargetDeleteDate, '|x|', 't1.'), ' AS Date) AS DateTime2))')
                                        ELSE CONCAT('CAST(',Replace(@SQL_TableTargetDeleteDate	,'|x|','t1.'),' as DateTime2)')
                                    end,' as ',Replace(@SQL_TableTargetDeleteDate,'|x|',''),'
								,t1.LastChangeOnDate
								,t1.LastChange
							from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'2 t1
								join ', @SQL_TableTargetString, '_TEMP',@TEMPPraefix,'_SchluesselID t98 on ',Replace(@SQL_TableTargetID,'|x|','t1.'), '=', Replace(@SQL_TableTargetID,'|x|','t98.'),'
							',case when @Historisierung>0 then Concat('
								join ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'2_hist t99 on ',Replace(@SQL_TableTargetID,'|x|','t1.'), '=', Replace(@SQL_TableTargetID,'|x|','t99.'),'
									and ',Replace(@SQL_TableTargetValidFrom,'|x|','t1.'),'=',Replace(@SQL_TableTargetValidFrom,'|x|','t99.'),'
									',case when @LastChangeOnDate=1 then ' and t99.LastChangeOnDate=1' else '' end,'
									')
							  else '' end,'
						',Replace(@SQL_TableTarget_Join,'|x|','t1.'),'
						where 1=1
						',case when @Historisierung>0 then concat('
							and DATEDIFF(d,',Replace(@SQL_TableTargetValidFrom,'|x|','t1.'),',',Replace(@SQL_TableTargetValidTo,'|x|','t1.'),')>=0
							and DATEDIFF(d,',Replace(@SQL_TableTargetValidFrom,'|x|','t1.'),',',Replace(@SQL_TableTargetStornoDate,'|x|','t1.'),')>0
							and DATEDIFF(d,',Replace(@SQL_TableTargetValidFrom,'|x|','t1.'),',',Replace(@SQL_TableTargetDeleteDate,'|x|','t1.'),')>0')
						else '' end,'
						',case when len(Replace(@SQL_TableTarget_Where,'|x|','t1.'))>0 then concat(' and ',Replace(@SQL_TableTarget_Where,'|x|','t1.')) else '' end,'
						');

			EXEC(@SQL+@SQL1+@SQL2+@SQL3);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep='XP540', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepSQL3=@SQL3, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke

			SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
XP550:
			SET @StepText=  Concat('','Zeilenanzahl der Tabelle [', @SQL_TableTargetString, '_TEMP',@TEMPPraefix,'] ermitteln.')
			SET @SQL=Concat('SELECT @Zeilenanzahl =(SELECT max(rows) as rowcnt 
								FROM ',@SQL_TableTargetDB,'.sys.partitions WHERE object_id=OBJECT_ID(''', @SQL_TableTargetString, '_TEMP',@TEMPPraefix,''', ''U''))')
	
			EXEC sp_EXECutesql @SQL, N'@Zeilenanzahl bigint OUT', @Zeilenanzahl OUT;
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep='XP550', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke

			SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
XP560:
			SET @StepText=  Concat('','Tabelle [',@SQL_TableTargetString,'] in [',@SQL_TableTargetString,'_DELTA] speichern.')

			SET @SQL1 = CONCAT('

				SELECT @SQL2 = (SELECT STRING_AGG(name,'','') WITHIN GROUP (ORDER BY column_id ASC) AS Name FROM sys.columns WHERE object_id = OBJECT_ID(''', @SQL_TableTargetString, '_DELTA'', ''U''))

			')

			EXEC sp_EXECutesql @SQL1, N'@SQL2 nVarChar(max) OUT', @SQL2 OUT;

			SET @SQL=Concat('

				SET IDENTITY_INSERT ',@SQL_TableTargetString,'_DELTA ON

				Insert into ',@SQL_TableTargetString,'_DELTA (', @SQL2, ')
				Select t1.* 
				from ',@SQL_TableTargetString,' t1
					join (
						Select distinct ',Replace(@SQL_TableTargetID,'|x|',''),' as ID 
						from ',@SQL_TableTargetString,'_TEMP',@TEMPPraefix,'
						) t2 on ',Replace(@SQL_TableTargetID,'|x|','t1.'), '=t2.ID
					join (
						Select distinct ',Replace(@SQL_TableTargetID,'|x|',''),' as ID 
						from ',@SQL_TableTargetString,' 
						where ',Replace(@SQL_TableTargetValidFrom,'|x|',''),' >= cast(dateadd(d,-',@DeltaDays,',cast(Getdate() as date)) as DateTime2)
						) t3 on ',Replace(@SQL_TableTargetID,'|x|','t1.'), '=t3.ID
			');	

			EXEC(@SQL);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep='XP560', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke

			SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
XP570:
			SET @StepText=  Concat('','View [',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,'_DELTA_VIEW] auf Tabelle [',@SQL_TableTargetString,'_DELTA] umsteuern und [',@SQL_TableTargetString,'_DELTA_BACKUP] löschen.')
			SET @SQL =Concat('Use ',@SQL_TableTargetDB,';

							  EXEC(''CREATE or ALTER VIEW ',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,'_DELTA_VIEW AS Select * from ',@SQL_TableTargetString,'_DELTA'');
			
							  Drop table if exists ',@SQL_TableTargetString,'_DELTA_BACKUP;
							 ');
			
			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC #LogStep @LogID=@LogID, @LogStep='XP570', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler

			if @Fehler>0
				goto Fehlermarke

			SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''

		end

	If @PostProcessing=1 
		Begin
NP1:
	
			if len(@SQL_PostProcessing1)>10
				Begin
					SET @StepText=Concat('','Ausführung Nachprozess 1')
					EXEC(@SQL_PostProcessing1+@SQL_PostProcessing11);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='NP1', @LogStepText=@StepText, @LogTableProcessMode=@Ladeverfahren, @LogStepSQL=@SQL_PostProcessing1, @LogStepSQL1=@SQL_PostProcessing11, @LogStepRows=@RowCount, @LogStepError=@Fehler
					if @Fehler>0
						goto Fehlermarke
				End
NP2:
			if len(@SQL_PostProcessing2)>10
				Begin
					SET @StepText=Concat('','Ausführung Nachprozess 2')
					EXEC(@SQL_PostProcessing2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='NP2', @LogStepText=@StepText, @LogStepSQL=@SQL_PostProcessing2, @LogStepRows=@RowCount, @LogStepError=@Fehler
					if @Fehler>0
						goto Fehlermarke
				End
NP3:
			if len(@SQL_PostProcessing3)>10
				Begin
					SET @StepText=Concat('','Ausführung Nachprozess 3')
					EXEC(@SQL_PostProcessing3);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='NP3', @LogStepText=@StepText, @LogStepSQL=@SQL_PostProcessing3, @LogStepRows=@RowCount, @LogStepError=@Fehler
					if @Fehler>0
						goto Fehlermarke
				End
NP4:
			if len(@SQL_PostProcessing4)>10
				Begin
					SET @StepText=Concat('','Ausführung Nachprozess 4')
					EXEC(@SQL_PostProcessing4);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='NP4', @LogStepText=@StepText, @LogStepSQL=@SQL_PostProcessing4, @LogStepRows=@RowCount, @LogStepError=@Fehler
					if @Fehler>0
						goto Fehlermarke
				End
NP5:
			if len(@SQL_PostProcessing5)>10
				Begin
					SET @StepText=Concat('','Ausführung Nachprozess 5')
					EXEC(@SQL_PostProcessing5);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC #LogStep @LogID=@LogID, @LogStep='NP5', @LogStepText=@StepText, @LogStepSQL=@SQL_PostProcessing5, @LogStepRows=@RowCount, @LogStepError=@Fehler
					if @Fehler>0
						goto Fehlermarke
				End
		end

AP0:
		Set @Konfiguration= concat('
				Delay				:',@DELAY,'
				MaxDelay			:',@MaxDelay,'
				MaxDelayTimestamp	:',@MaxDelayTimestamp,'
				Zyklus				:',@DaysToFullLoad,'
				TestDurchLauf		:',@TestLoop,'
				Delta				:',@DeltaDays,'
				Fullload			:',@FullloadYears,'
				Ladeverfahren		:',@Ladeverfahren,'
				CDPOS_laden			:',@CDPOS_laden,'
				LastChangeFromTarget:',@LastChangeFromTarget,'
				HashAbgleich_ct		:',@HashAbgleich_ct,'
				Historisierung		:',@Historisierung,'
				PreProcessing		:',@PreProcessing,'
				PostProcessing		:',@PostProcessing,'
				TEMPPraefix			:',@TEMPPraefix,'
				TEMPLoeschen		:',@TEMPLoeschen,'
				StartStep			:',@StartStep,'
				gueltig_von			:',Replace(@SQL_TableTargetValidFrom,'|x|',''),'
				gueltig_bis			:',Replace(@SQL_TableTargetValidTo,'|x|',''),'
				Source Tabelle		:',@SQL_TableSourceString,'
				Target Tabelle		:',@SQL_TableTargetString,'
				Logging Tabelle		:',@SQL_TableLoggingString,'
				Status Tabelle		:',@SQL_TableTabStatusString,'
				QlikLoad Tabelle	:',@SQL_TableQlikLoadString,'
				TargetString		:',@SQL_TableLoggingString,'
				LastChangeOnDate	:',@LastChangeOnDate,'
				ValidAfterStorno	:',@ValidBeforeStorno,'
				ValidToStorno		:',@ValidToStorno,'
				LastLoad			:',convert(nvarchar,@LastLoadLocal,126),'
				LastFullLoad		:',convert(nvarchar,@LastFullLoadLocal,126),'
				TableCTLastUpdate	:',convert(nvarchar,@TableCTLastUpdateLocal,126),'
				Spalten				:',Replace(@FieldList1,'|x|',''),'
				')
AP1:
		SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
		SET @StepText=Concat('','Abschluss: Spaltenliste erstellen')
		SET @SQL=Concat('SELECT @FieldList5=COALESCE(@FieldList5+N''',CHAR(13),','', N'''') + case c.name 
				when ''',Replace(@SQL_TableTargetValidFrom,'|x|',''),''' then ''',Replace(@SQL_TableTargetValidFrom,'|x|',''),' as ',@SQL_TableTargetName,'_',Replace(@SQL_TableTargetValidFrom,'|x|',''),'''
				when ''',Replace(@SQL_TableTargetValidTo,'|x|',''),''' then ''',Replace(@SQL_TableTargetValidTo,'|x|',''),' as ',@SQL_TableTargetName,'_',Replace(@SQL_TableTargetValidTo,'|x|',''),'''
				else c.name  end
								from ',@SQL_TableTargetDB,'.sys.views v
									join ',@SQL_TableTargetDB,'.sys.columns as c on v.object_id=c.object_id 
									join ',@SQL_TableTargetDB,'.sys.types t ON c.user_type_id=t.user_type_id
								where v.object_id = object_id(''',@SQL_TableTargetString,'_VIEW'',''V'')
								and c.name not in (''RowID'',''Rang'',''HashID''
								,''LastChangeOnDate''
								,''LastChange''
								,''', replace(@SQL_TableTargetCreateDate,'|x|',''), '''
								,''', replace(@SQL_TableTargetUpDate,'|x|',''), '''
								,''', replace(@SQL_TableTargetStornoFlag,'|x|',''), '''
								,''', replace(@SQL_TableTargetStornoDate,'|x|',''), '''
								,''', replace(@SQL_TableTargetDeleteFlag,'|x|',''), '''
								,''', replace(@SQL_TableTargetDeleteDate,'|x|',''), ''')
								')
		
		EXEC sp_EXECutesql @SQL, N'@FieldList5 nvarchar(max) OUT', @FieldList5 OUT;
		SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
		EXEC #LogStep @LogID=@LogID, @LogStep='AP1', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepRows=@RowCount, @LogStepError=@Fehler
		if @Fehler>0
			goto Fehlermarke
AP2:
		SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
		SET @StepText=Concat('','Abschluss: Tabellenbeziehungen in [',@SQL_TableRelationTreeString,'] eintragen.')
		SET @SQL=Concat('
						Delete ',@SQL_TableRelationTreeString,'
						where [TargetTableDB]	=''',@SQL_TableTargetDB,'''
						and [TargetTableSchema]	=''',@SQL_TableTargetSchema,'''
						and [TargetTableName]	=''',@SQL_TableTargetName,'''
					
						Insert into ',@SQL_TableRelationTreeString,'
						Values (
									(SELECT Distinct isnull(MAX(RelationID),1)+1 FROM ',@SQL_TableRelationTreeString,')
									,''',@SQL_TableTargetDB,'''
									,''',@SQL_TableTargetSchema,'''
									,''',@SQL_TableTargetName,'''
									,',Object_id(@SQL_TableTargetString,'U'),'
									,''',replace(@SQL_TableTargetID,'|x|',''),'''
									,''RowID''
									,''', CONVERT(nVarChar, CAST(@SnapshotTimestampUTC AT TIME ZONE 'UTC' AT TIME ZONE 'Central European Standard Time' AS DateTime2), 126), '''
									,(SELECT max(p.rows) as Zeilen
									FROM sys.tables AS tbl
									JOIN sys.indexes as i ON i.object_id = tbl.object_id
									JOIN sys.partitions as p ON p.object_id = i.object_id and p.index_id = i.index_id
									JOIN sys.allocation_units as a ON a.container_id = p.partition_id
									where tbl.object_id=',Object_id(@SQL_TableTargetString,'U'),')
									,(SELECT ISNULL(8 * SUM(CASE WHEN a.type <> 1 THEN a.used_pages WHEN p.index_id < 2 THEN a.data_pages ELSE 0 END),0.0) as Speicherplatz
									FROM sys.tables AS tbl
									JOIN sys.indexes as i ON i.object_id = tbl.object_id
									JOIN sys.partitions as p ON p.object_id = i.object_id and p.index_id = i.index_id
									JOIN sys.allocation_units as a ON a.container_id = p.partition_id
									where tbl.object_id=',Object_id(@SQL_TableTargetString,'U'),')	
									,''',@SQL_TableSourceDB,'''
									,''',@SQL_TableSourceSchema,'''
									,''',@SQL_TableSourceName,'''
									,',Object_id(@SQL_TableSourceString,'U'),'
									,''',replace(@SQL_TableSourceID,'|x|',''),' as ', replace(@SQL_TableTargetID,'|x|',''),'''
									,Null
									,''',convert(nvarchar,@TableCTLastUpdateLocal,126),'''
									,Null
									,Null
									,',@LastChangeOnDate,'
									,''valid''
									,''',@Ladeverfahren,'''
									,',@LogID,'
									,''',@SQL_TableLoggingString,'''
								)
						')

		EXEC(@SQL);
		SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
		EXEC #LogStep @LogID=@LogID, @LogStep='AP2', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepRows=@RowCount, @LogStepError=@Fehler

		if @Fehler>0
			goto Fehlermarke

		SET @SQL=''; SET @SQL1='';SET @SQL2=''; SET @SQL3=''
AP3:
		If @TEMPLoeschen=1
			Begin

				SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
				SET @StepText=Concat('','Abschluss: [%TEMP%]-Tabellen löschen.')
				SET @SQL=Concat('SELECT @SQL1=COALESCE(@SQL1+N''
				'', N'''') + isnull(''Drop Table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.''+ t1.name +'';'','''')
										from ',@SQL_TableTargetDB,'.sys.tables t1
											join ',@SQL_TableTargetDB,'.sys.schemas as t2 on t1.schema_id=t2.schema_id and t2.name=''',@SQL_TableTargetSchema,'''
										where t1.name like ''',@SQL_TableTargetName,'%'' and t1.name like ''%_TEMP%''')

				EXEC sp_EXECutesql @SQL, N'@SQL1 nvarchar(max) OUT', @SQL1 OUT;
		
				EXEC(@SQL1);
				SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
				EXEC #LogStep @LogID=@LogID, @LogStep='AP3', @LogStepText=@StepText, @LogStepSQL=@SQL1, @LogStepRows=@RowCount, @LogStepError=@Fehler
				if @Fehler>0
					goto Fehlermarke

			end

AP4:
	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
	SET @StepText=Concat('','Abschluss: Aktualisierung der Spalte [QlikLoad] in der Log-Tabelle [',@SQL_TableRelationTreeString,'].')
	SET @FieldList5=Concat('Select ',CHAR(13),@FieldList5,CHAR(13),' FROM ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,'_VIEW ',CHAR(13),case when @LastChangeOnDate=1 then 'WHERE LastChangeOnDate=1' else '' end)
	SET @SQL=Concat('	
						Update ',@SQL_TableRelationTreeString,'
						SET 
							QlikLoad = ''',@FieldList5,''' 
						from ',@SQL_TableRelationTreeString,'
						where TargetObjectID=',Object_id(@SQL_TableTargetString,'U'),'
					')

	EXEC(@SQL);
	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep='AP4', @LogStepText=@StepText, @LogStepSQL=@SQL, @LogStepRows=@RowCount, @LogStepError=@Fehler
	if @Fehler>0
		goto Fehlermarke

AP5:
	SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
	SET @StepPraefix='AP5'
	SET @StepText=Concat('','Abschluss: Aktualisierung der Spalte [Konfig] in der Log-Tabelle [',@SQL_TableRelationTreeString,'].')

	SET @SQL_Konfig=concat('Update ',@SQL_TableRelationTreeString,'
		Set Konfig=''
		Use ',@SQL_TableTargetDB,';
		Execute ',@SQL_TableTargetSchema,'.[UpdateBaseTable_Aenderungshistorie]
		',@SQL_Konfig)
	
	SET @SQL_Konfig10=concat(@SQL_Konfig10, '
	''
	from ',@SQL_TableRelationTreeString,' where TargetObjectID=',Object_id(@SQL_TableTargetString,'U')
	)

	EXEC(@SQL_Konfig+@SQL_Konfig1+@SQL_Konfig2+@SQL_Konfig3+@SQL_Konfig4+@SQL_Konfig5+@SQL_Konfig6+@SQL_Konfig7+@SQL_Konfig8+@SQL_Konfig9+@SQL_Konfig10);

	SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
	EXEC #LogStep @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, 
			@LogStepSQL=@SQL_Konfig,@LogStepSQL1=@SQL_Konfig1, @LogStepSQL2=@SQL_Konfig2, @LogStepSQL3=@SQL_Konfig3, 
			@LogStepSQL4=@SQL_Konfig4,@LogStepSQL5=@SQL_Konfig5, @LogStepSQL6=@SQL_Konfig6, @LogStepSQL7=@SQL_Konfig7, 
			@LogStepSQL8=@SQL_Konfig8,@LogStepSQL9=@SQL_Konfig9, @LogStepSQL10=@SQL_Konfig10, 
			@LogStepRows=@RowCount, @LogStepError=@Fehler 
	
	if @Fehler>0
		goto Fehlermarke

	SET @SQL_Konfig=''; SET @SQL_Konfig1=''; SET @SQL_Konfig2=''; SET @SQL_Konfig3=''; SET @SQL_Konfig4=''; SET @SQL_Konfig5=''; SET @SQL_Konfig6=''; SET @SQL_Konfig7=''; SET @SQL_Konfig8=''; SET @SQL_Konfig9=''; SET @SQL_Konfig10=''

	If DATALENGTH(@TestLoop)>0
		SET @Ladeverfahren='T'

	EXEC #LogStep @LogID=@LogID,
			@LogTableProcessStatus='FINISHED',
			@LogStep='END',
			@LogStepSQL=@Konfiguration,
			@LogStepRows=@Zeilenanzahl,
			@LogStepStatus='FINISHED'

goto Endmarke

Fehlermarke:

		Set @SQL= concat('
						Delay				:',@DELAY,'
						MaxDelay			:',@MaxDelay,'
						MaxDelayTimestamp	:',@MaxDelayTimestamp,'
						Zyklus				:',@DaysToFullLoad,'
						TestDurchLauf		:',@TestLoop,'
						Delta				:',@DeltaDays,'
						Fullload			:',@FullloadYears,'
						Ladeverfahren		:',@Ladeverfahren,'
						CDPOS_laden			:',@CDPOS_laden,'
						LastChangeFromTarget:',@LastChangeFromTarget,'
						HashAbgleich_ct		:',@HashAbgleich_ct,'
						Historisierung		:',@Historisierung,'
						PreProcessing		:',@PreProcessing,'
						PostProcessing		:',@PostProcessing,'
						TEMPPraefix			:',@TEMPPraefix,'
						TEMPLoeschen		:',@TEMPLoeschen,'
						StartStep			:',@StartStep,'
						gueltig_von			:',Replace(@SQL_TableTargetValidFrom,'|x|',''),'
						gueltig_bis			:',Replace(@SQL_TableTargetValidTo,'|x|',''),'
						Source Tabelle		:',@SQL_TableSourceString,'
						Target Tabelle		:',@SQL_TableTargetString,'
						Logging Tabelle		:',@SQL_TableLoggingString,'
						Status Tabelle		:',@SQL_TableTabStatusString,'
						QlikLoad Tabelle	:',@SQL_TableQlikLoadString,'
						TargetString		:',@SQL_TableLoggingString,'
						LastChangeOnDate	:',@LastChangeOnDate,'
						ValidAfterStorno	:',@ValidBeforeStorno,'
						ValidToStorno		:',@ValidToStorno,'
						LastLoad			:',convert(nvarchar,@LastLoadLocal,126),'
						LastFullLoad		:',convert(nvarchar,@LastFullLoadLocal,126),'
						TableCTLastUpdate	:',convert(nvarchar,@TableCTLastUpdateLocal,126),'
						Spalten				:',Replace(@FieldList1,'|x|',''),'
						')

if @Fehler<>99993
	Begin
		Print '#######################################################################'
		Print 'FEHLER!!!!!!!!!!!!!!!!!!!!!!!'
		Print @@Error
		Print '#######################################################################'
		EXEC #LogStep @LogID=@LogID,
				@LogTableProcessStatus='ERROR',
				@LogStep='END',
				@LogStepSQL=@SQL,
				@LogStepRows=@Zeilenanzahl,
				@LogStepStatus='ERROR',
				@LogStepError=@Fehler,
				@LogStepErrorText=@FehlerText

	End
else
	Begin
		Print '#######################################################################'
		Print 'Ergbnisstabelle ist gemäß @MaxDelay Parameter aktuell!'
		Print '#######################################################################'
		EXEC #LogStep @LogID=@LogID,
				@LogTableProcessStatus='NOLOAD',
				@LogStep='END',
				@LogStepSQL=@Konfiguration,
				@LogStepRows=@Zeilenanzahl,
				@LogStepStatus='FINISHED',
				@LogStepError=@Fehler,
				@LogStepErrorText=@FehlerText
	End

Endmarke:
end



