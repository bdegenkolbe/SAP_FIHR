USE [Analysen]
GO

/*
exec dbo.UpdateBaseTable_Bewegungen_Aenderungshistorie @Ladeverfahren = 'F', @PreProcessing=0, @MainProcessing=0, @PostProcessing=1, @TEMPPraefix=62944979, @CDPOS_laden=0
exec dbo.UpdateBaseTable_Bewegungen_Aenderungshistorie @Ladeverfahren = 'F', @PreProcessing=1, @MainProcessing=1, @PostProcessing=1, @TEMPPraefix=62944979, @CDPOS_laden=1
exec dbo.UpdateBaseTable_Bewegungen_Aenderungshistorie @Ladeverfahren = 'FN', @PreProcessing=0, @MainProcessing=1, @PostProcessing=0, @TEMPPraefix=331499193, @TEMPLoeschen=0, @CDPOS_laden=0, @TestLoop='Top 1000', @SQL_TableSource_Where = 'cast(|x|FALNR as bigint)=18402265', @StartStep='AP5'
Select * from Analysen.dbo.Bewegungen_Aenderungshistorie_Test
Select * from Analysen.dbo.Bewegungen_Aenderungshistorie  where Fallnummer=18487250 and bewegung_nummer in (5,9)
Select * from replicate.sap.nbew where FALNR=16797401 and lfdnr in (5,9)
*/

CREATE or ALTER PROC [dbo].[UpdateBaseTable_Bewegungen_Aenderungshistorie]
	@DELAY int						=10,	--> Greift im Fasttrack auch die Daten n-Tage vor dem letzten Ladevorgang ab. 
	@DaysToFullLoad int				=7,		--> Aller wieviel Tage soll ein Fullload durchgeführt werden?
	@TestLoop nvarchar(100)			='',	--> bspw. 'Top 100' für 100 Testdatensätze
	@DeltaDays as int				=1,		--> Delta-Load beinhaltet n volle Tage 
	@FullloadYears as int			=5,		--> Jahre die als Fullload geladen werden sollen, 0=Delta-Load
	@Ladeverfahren as nvarchar(2)	='',	--> Wenn 'F' dann Fulload, wenn 'D' dann Deltaload, Sonst entscheidet das Skript automatische über das Ladeverfahren anhand der Einstellungen
	@CDPOS_laden as int				=1,		--> Wenn 1 wird die CDPOS bei Änderungen geladen, wenn 2 wird CDPOS immer geladen, wenn 0 wird CDPOS nicht geladen
	@LastChangeFromTarget as int	=0,		--> Wenn 1 wird der letzte Änderungszeitpunkt aus der TargetTabelle berechnet - langsam/0=Änderungszeitpunkt wird aus den SYS-Tabellen berechnet
	@HashAbgleich_ct as int			=1,		--> 1=Nur relevanten Änderungen in den ct Tabellen werden mit einem HASH über die ausgewählten Spalten verarbeitet/0=keine Hash-Prüfung im ersten Schritt
	@Historisierung as int			=1,		--> 1=Historisierte Werte aus CT-Tabellen und der CDPOS werden abgefragt / 0=keine historisierten Werte
	@PreProcessing as int			=1,		--> 1=Vorprozesse werden ausgeführt
	@MainProcessing as int			=1,		--> 1=Hauptprozesse werden ausgeführt
	@PostProcessing as int			=1,		--> 1=Nachprozesse werden ausgeführt
	@TEMPPraefix as nvarchar(100)	='New',	--> 'New' wird eine neue TempID für alle Temptabellen vergeben. Insofern ein Wert für @TEMPPraefix=108512190 angegeben wird, wird dieser Wert für alle Temp-Tabellen verwendet.
	@TEMPLoeschen as int			=1,		--> 1=Tempdateien werden gelöscht
	@StartStep as varchar(10)		='',	--> Startet mit Prozessschritt bspw. 'XP270'
	@LastChangeOnDate as int		=1,		--> Wenn 1 werden nur die letzten Änderungen eines Tages ausgewertet. Wenn 0 werden alle datensätze ausgewertet.
	@ValidToStorno as int			=1,		--> Wenn 1 wird der Gültigkeitszeitraum des Datensatzes zum Stornozeitpunkt beendet (Standard). Wenn 0 ist der Datensatz auch nach dem Stornozeitpunkt gültig.
	@ValidBeforeStorno as int		=1,		--> Wenn 1 sind alle Datensätze eine Zeiteinheit vor einem Storno gültig (Standard). Wenn 0 sind alle Datensätze genau bis zum Storno gültig.

	@SQL_TableSource_Where as nvarchar(max) = '', --> Filter der Originaltabelle ohne Where-Befehl --> 'cast(|x|ZUONR as bigint) in (17942266)'
	@SQL_TableTargetDB as nvarchar(200)		= 'Analysen',	--> Übergabeparameter für DIAS
	@SQL_TableTargetSchema as nvarchar(200)	= 'dbo'		--> Übergabeparameter für DIAS
	
as
Begin

	PRINT 'Starte Skripabarbeitung für Prozedur [UpdateBaseTable_Bewegungen_Aenderungshistorie]'
	
	DECLARE @SQL_PreProcessing1 as nvarchar(max)
	DECLARE @SQL_PreProcessing2 as nvarchar(max)
	DECLARE @SQL_PreProcessing3 as nvarchar(max)
	DECLARE @SQL_PreProcessing4 as nvarchar(max)
	DECLARE @SQL_PreProcessing5 as nvarchar(max)
	DECLARE @SQL_PostProcessing1 as nvarchar(max)
	DECLARE @SQL_PostProcessing2 as nvarchar(max)
	DECLARE @SQL_PostProcessing3 as nvarchar(max)
	DECLARE @SQL_PostProcessing4 as nvarchar(max)
	DECLARE @SQL_PostProcessing5 as nvarchar(max)

	DECLARE @SQL as nvarchar(max)
	DECLARE @SQL1 as nvarchar(max)
	DECLARE @SQL2 as nvarchar(max)

	DECLARE @SQL_TableSourceDB as nvarchar(200)
	DECLARE @SQL_TableSourceSchema as nvarchar(200)
	DECLARE @SQL_TableSourceName as nvarchar(200)
	DECLARE @SQL_TableSourceString as nvarchar(200)
	DECLARE @SQL_TableSourceFields as nvarchar(max)
	DECLARE @SQL_TableSourceID as nvarchar(200)
	DECLARE @SQL_TableSourceCreateDate as nvarchar(500)
	DECLARE @SQL_TableSourceUpDate as nvarchar(500)
	DECLARE @SQL_TableSourceStornoDate as nvarchar(500)
	DECLARE @SQL_TableSourceStornoField as nvarchar(500)
	DECLARE @SQL_TableSourceStornoFlag as nvarchar(500)

	DECLARE @SQL_TableSource_Join as nvarchar(max)
	DECLARE @SQL_TableSource_Kopf as nvarchar(max)
	DECLARE @SQL_TableSource_Fuss as nvarchar(max)

	DECLARE @SQL_TableTargetString as nvarchar(200)
	DECLARE @SQL_TableTargetFields as nvarchar(max)
	DECLARE @SQL_TableTargetID as nvarchar(200)
	DECLARE @SQL_TableTarget_Join as nvarchar(max)
	DECLARE @SQL_TableTarget_Where as nvarchar(max)
	DECLARE @SQL_TableTargetDefinition1 as nvarchar(max)
	DECLARE @SQL_TableTargetDefinition2 as nvarchar(max)
	DECLARE @SQL_TableTargetDefinition3 as nvarchar(max)
	DECLARE @SQL_TableTargetUpDate as nvarchar(500)
	DECLARE @SQL_TableTargetCreateDate as nvarchar(500)
	DECLARE @SQL_TableTargetStornoDate as nvarchar(500)
	DECLARE @SQL_TableTargetStornoFlag as nvarchar(500)
	DECLARE @SQL_TableTargetName as nvarchar(200)

	DECLARE @CDPOS_TableID as nvarchar(200)

	DECLARE	@SQL_TableLoggingName		as nvarchar(299)
	DECLARE @SQL_TableLoggingString		as nvarchar(299)
	DECLARE @SQL_TableTabStatusName		as nvarchar(299)
	DECLARE @SQL_TableTabStatusString	as nvarchar(299)
	DECLARE @SQL_TableQlikLoadName		as nvarchar(299)
	DECLARE @SQL_TableQlikLoadString	as nvarchar(299)
	DECLARE @SQL_TableRelationTreeString	as nvarchar(299)
	
	DECLARE @Zeit datetime
	DECLARE @Start datetime
	DECLARE @Fehler as int
	DECLARE @Datenweg int
	DECLARE @Zaehler as int
	DECLARE @Praefix as nvarchar(100)
	DECLARE @Zeilenanzahl as int
	DECLARE @StepPraefix as nvarchar(100)
	DECLARE @RowCount as bigint
	DECLARE @StepText nvarchar(500)
	DECLARE @LogID bigint

	If LEN(Trim(@SQL_TableLoggingString))=0 or @SQL_TableLoggingString is null
		SET @SQL_TableLoggingString=	concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_Log')

	If LEN(Trim(@SQL_TableTabStatusString))=0 or @SQL_TableTabStatusString is null
		SET @SQL_TableTabStatusString=	concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_TabStatus')

	If LEN(Trim(@SQL_TableQlikLoadString))=0 or @SQL_TableQlikLoadString is null
		SET @SQL_TableQlikLoadString=	concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_QlikLoad')

	If LEN(Trim(@SQL_TableRelationTreeString))=0 or @SQL_TableRelationTreeString is null
		SET @SQL_TableRelationTreeString=	concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_TabTree')

	Execute dbo.Konfiguration 
		@SQL_TableTargetDB =@SQL_TableTargetDB,
		@SQL_TableTargetSchema =@SQL_TableTargetSchema,
		@SQL_TableLoggingString =@SQL_TableLoggingString,
		@SQL_TableTabStatusString =@SQL_TableTabStatusString,
		@SQL_TableQlikLoadString =@SQL_TableQlikLoadString,
		@SQL_TableRelationTreeString =@SQL_TableRelationTreeString, 
		@Datenweg=@Datenweg OUTPUT; 

	If @TEMPPraefix='New' 
		Select @TEMPPraefix=cast(rand()*cast(Getdate() as int)*10000 as int)
	
	SET @Start=Getdate();
	SET @SQL_TableSourceDB			= 'replicate'
	SET @SQL_TableSourceSchema		= 'sap'

	Execute dbo.Logging @LogID=@LogID Output, 
						@LogTableName='Bewegung',
						@LogTableProcess='Procedure',
						@LogTableProcessMode='INIT',
						@LogTableProcessStatus='START',
						@LogStep='START',
						@LogStepText='START',
						@LogStepStart=@Start,
						@LogStepSQL='',
						@LogStepRows=0,
						@LogStepStatus='START'

	if @PreProcessing=1
		Begin
Pre10:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Pre10'
			SET @StepText= Concat('','Start: Filtertabelle [Filter_Fallnummer] aufbauen.')

			EXECUTE dbo.UpdateFilterTable_Fallnummer
			@Ladeverfahren=@Ladeverfahren, @TestLoop=@TestLoop, @FullloadYears=@FullloadYears,
			@SQL_TableSourceDB=@SQL_TableSourceDB, @SQL_TableSourceSchema=@SQL_TableSourceSchema, 
			@SQL_TableTargetDB=@SQL_TableTargetDB, @SQL_TableTargetSchema=@SQL_TableTargetSchema, @SQL_TableTargetName='Filter_Fallnummer'

			SET @SQL=concat('EXECUTE dbo.UpdateFilterTable_Fallnummer,
			@Ladeverfahren=',@Ladeverfahren,', @TestLoop=',@TestLoop,', @FullloadYears=',@FullloadYears,',
			@SQL_TableSourceDB=',@SQL_TableSourceDB,', @SQL_TableSourceSchema=',@SQL_TableSourceSchema,', 
			@SQL_TableTargetDB=',@SQL_TableTargetDB,', @SQL_TableTargetSchema=',@SQL_TableTargetSchema,', @SQL_TableTargetName=''Filter_Fallnummer''')

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PreProcessing', @LogStepError=@Fehler 

Pre20:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Pre20'
			SET @StepText= Concat('','UpdateBaseTable [Leistung_PEPP_Bezugsgroesse]')
			--TNPEPP: Leistung_PEPP_Bezugsgroesse
			--Select * from replicate.sap.tnpepp
			--Select * from Leistung_PEPP_Bezugsgroesse where Fachrichtung=2900
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=0,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='TNPEPP',
					@SQL_TableSourceFields='MANDT,EINRI,FACHR,BASENT,BEGDT,ENDDT',
					@SQL_TableSourceID='concat(|x|MANDT,|x|EINRI,|x|FACHR)',
					@SQL_TableSourceCreateDate=	'case when year(|x|BEGDT) between 1990 and 2099 and try_cast(|x|BEGDT as datetime) is not null then cast(|x|BEGDT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end ',
					@SQL_TableSourceUpDate=		'case when year(|x|ENDDT) between 1990 and 2099 and try_cast(|x|ENDDT as datetime) is not null then cast(|x|ENDDT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end ',
					@SQL_TableSourceStornoDate=	'case when year(|x|ENDDT) between 1990 and 2099 and try_cast(|x|ENDDT as datetime) is not null then cast(|x|ENDDT as datetime) + cast(''23:59:59'' as datetime) else cast(''31.12.2099 23:59:59'' as datetime) end ',
					@SQL_TableSourceStornoFlag=	'case when year(|x|ENDDT) between 1990 and 2099 and try_cast(|x|ENDDT as datetime) is not null then 1 else 0 end',
					@SQL_TableSource_Where='',
					@ValidToStorno	= 1, @ValidBeforeStorno=0,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Leistung_PEPP_Bezugsgroesse',
					@SQL_TableTargetID='|x|Leistung_PEPP_FachrID',
					@SQL_TableTargetDefinition1='
					|x|FACHR as Fachrichtung
					,|x|BASENT as Bezugsgroesse',
					@CDPOS_laden=0, @CDPOS_TableID	= ''

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler 

Pre30:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Pre30'
			SET @StepText= Concat('','UpdateBaseTable [Bewegung_Grund_Bezeichnung]')
			--TN14R: Bewegung_Grund_Text
			--Select * from replicate.sap.TN14R
			--Select * from Bewegung_Grund_Text
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@CDPOS_laden=0,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='TN14R',
					@SQL_TableSourceFields='BEZEI',
					@SQL_TableSourceID='CONCAT(|x|MANDT,|x|BEWTY,|x|POSIT,|x|GRUND)',
					@SQL_TableSourceCreateDate	='cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceUpDate		='cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceStornoDate	='cast(''31.12.2099 23:59:59'' as datetime)', @SQL_TableSourceStornoFlag='0',	
					@ValidToStorno	= 1, @ValidBeforeStorno=0,
					@SQL_TableSource_Where		= '|x|SPRAS=''D''',
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Bewegung_Grund_Bezeichnung',
					@SQL_TableTargetID='|x|Bewegung_GrundID',
					@SQL_TableTargetDefinition1 = 'BEZEI as KurzText',
					@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler 

Pre40:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Pre40'
			SET @StepText= Concat('','UpdateBaseTable [Bewegung_Typ_Text]')
			--TN14T: Bewegung_Typ_Text 00:00:07
			--Select * from replicate.sap.TN14T
			--Select * from Bewegung_Typ_Text
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@CDPOS_laden=0,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='TN14T',
					@SQL_TableSourceFields='BEWTX',
					@SQL_TableSourceID='CONCAT(|x|MANDT,|x|EINRI,|x|BEWTY)',
					@SQL_TableSourceCreateDate	='cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceUpDate		='cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceStornoDate	='cast(''31.12.2099 23:59:59'' as datetime)', @SQL_TableSourceStornoFlag='0',	
					@ValidToStorno	= 1, @ValidBeforeStorno = 0,
					@SQL_TableSource_Where		= '|x|SPRAS=''D''',
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Bewegung_Typ_Text',
					@SQL_TableTargetID='|x|Bewegung_TypID',
					@SQL_TableTargetDefinition1 = 'BEWTX as KurzText',
					@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler 

Pre50:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Pre50'
			SET @StepText= Concat('','UpdateBaseTable [Bewegung_Art_Text]')
			--TN14U: Bewegung_Art_Text 00:00:08
			--Select * from replicate.sap.TN14U
			--Select * from Bewegung_Art_Text
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@CDPOS_laden=0,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='TN14U',
					@SQL_TableSourceFields='BWATX',
					@SQL_TableSourceID='CONCAT(|x|MANDT,|x|EINRI,|x|BEWTY,|x|BWART)',
					@SQL_TableSourceCreateDate	='cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceUpDate		='cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceStornoDate	='cast(''31.12.2099 23:59:59'' as datetime)', @SQL_TableSourceStornoFlag='0',	
					@ValidToStorno	= 1, @ValidBeforeStorno = 0,
					@SQL_TableSource_Where		= '|x|SPRAS=''D''',
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Bewegung_Art_Text',
					@SQL_TableTargetID='|x|Bewegung_ArtID',
					@SQL_TableTargetDefinition1 = 'BWATX as KurzText',
					@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler 

Pre60:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Pre60'
			SET @StepText= Concat('','UpdateBaseTable [Bewegung_UnfallArt_Text]')
			--TN14V: Bewegung_UnfallArt_Text 00:00:08
			--Select * from replicate.sap.TN14V
			--Select * from Bewegung_UnfallArt_Text
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@CDPOS_laden=0,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='TN14V',
					@SQL_TableSourceFields='UNFTX',
					@SQL_TableSourceID='CONCAT(|x|MANDT,|x|EINRI,|x|UNFAR)',
					@SQL_TableSourceCreateDate	='cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceUpDate		='cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceStornoDate	='cast(''31.12.2099 23:59:59'' as datetime)', @SQL_TableSourceStornoFlag='0',	
					@ValidToStorno	= 1, @ValidBeforeStorno = 0,
					@SQL_TableSource_Where		= '|x|SPRAS=''D''',
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Bewegung_UnfallArt_Text',
					@SQL_TableTargetID='|x|Bewegung_UnfallArtID',
					@SQL_TableTargetDefinition1 = 'UNFTX as KurzText',
					@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler 

Pre70:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Pre70'
			SET @StepText= Concat('','UpdateBaseTable [Bewegung_Art_Kennzeichen]')
			--TN14B: Bewegung_Art_Kennzeichen 00:00:08
			--Select * from replicate.sap.TN14B
			--Select * from Bewegung_Art_Kennzeichen
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@CDPOS_laden=0,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='TN14B',
					@SQL_TableSourceFields='MANDT,BEWTY,BWART,BWGR1,BWGR2,TODKZ,NEUGB,ENTBI,BEGLT,BEGLM,AUFKH,ENTKH,VSTAT,NSTAT,TSTAT,AMBOP,OPERA,NOTKZ,STASP,KV_SP',
					@SQL_TableSourceID='CONCAT(|x|MANDT,|x|EINRI,|x|BEWTY,|x|BWART)',
					@SQL_TableSourceCreateDate	='cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceUpDate		='cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceStornoDate	='cast(''31.12.2099 23:59:59'' as datetime)', @SQL_TableSourceStornoFlag='0',	
					@ValidToStorno	= 1, @ValidBeforeStorno = 0,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Bewegung_Art_Kennzeichen',
					@SQL_TableTargetID='|x|Bewegung_ArtID',
					@SQL_TableTargetDefinition1 = '
					case when TODKZ=''X'' then 1 else 0 end as Tod
					,case when NEUGB=''X'' then 1 else 0 end as Neugeboren
					,case when ENTBI=''X'' then 1 else 0 end as Entbindung
					,case when BEGLT=''X'' and BWART<>''E'' then 1 else 0 end as Begleitung
					,case when BEGLM=''X'' then 1 else 0 end as Begleitung_Medizinisch
					,case when AUFKH=''X'' then 1 else 0 end as AufnahmeKH
					,case when ENTKH=''X'' and BWART<>''ER'' then 1 else 0 end as EntlassungKH
					,case when VSTAT=''X'' then 1 else 0 end as Vorstationaer
					,case when NSTAT=''X'' then 1 else 0 end as Nachstationaer
					,case when TSTAT=''X'' then 1 else 0 end as Teilstationaer
					,case when AMBOP=''X'' then 1 else 0 end as AmbulanteOP
					,case when OPERA=''X'' then 1 else 0 end as Operation
					,case when NOTKZ=''X'' then 1 else 0 end as Notfall
					,case when STASP=''X'' then 1 else 0 end as StatistikSperre
					,case when KV_SP=''X'' then 1 else 0 end as KVSperre
					,CONCAT(MANDT,BEWTY,1,BWGR1)	 as Bewegung_GrundID1
					,CONCAT(MANDT,BEWTY,3,BWGR2)	 as Bewegung_GrundID2',
					@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler 

Pre80:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Pre80'
			SET @StepText= Concat('','UpdateBaseTable [Behandlung_Kategorie_Eigenschaften]')
			--TN24: Behandlung_Kategorie_Eigenschaften 00:00:08
			--Select * from replicate.sap.TN24
			--Select * from Behandlung_Kategorie_Eigenschaften
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@CDPOS_laden=0,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='TN24',
					@SQL_TableSourceFields='BEGDT,ENDDT,FALAR,ACCCAT,INPAT,OUTPAT,DAYPAT',
					@SQL_TableSourceID='CONCAT(|x|MANDT,|x|EINRI,|x|BEKAT)',
					@SQL_TableSourceCreateDate	='cast(|x|BEGDT as datetime)',
					@SQL_TableSourceUpDate		='cast(|x|BEGDT as datetime)',
					@SQL_TableSourceStornoDate	='case when year(cast(|x|ENDDT as datetime)) between 1990 and year(getdate())+1 then cast(|x|ENDDT as datetime) + cast(''23:59:59'' as datetime) else cast(''31.12.2099 23:59:59'' as datetime) end', @SQL_TableSourceStornoFlag='0',	
					@ValidToStorno	= 1, @ValidBeforeStorno = 0,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Behandlung_Kategorie_Eigenschaften',
					@SQL_TableTargetID='|x|Behandlung_KategorieID',
					@SQL_TableTargetDefinition1 = '
					|x|FALAR as FallArt
					,|x|ACCCAT as Unterbringung
					,case when |x|INPAT=''X'' then 1 else 0 end as Stationaer
					,case when |x|OUTPAT=''X'' then 1 else 0 end as Ambulant
					,case when |x|DAYPAT=''X'' then 1 else 0 end as TagPatient',
					@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler 

Pre90:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Pre90'
			SET @StepText= Concat('','UpdateBaseTable [Behandlung_Kategorie_Text]')

			--TN24T: Behandlung_Kategorie_Text 00:00:08
			--Select * from replicate.sap.TN24T
			--Select * from Behandlung_Kategorie_Text
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@CDPOS_laden=0,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='TN24T',
					@SQL_TableSourceFields='BLTXT',
					@SQL_TableSourceID='CONCAT(|x|MANDT,|x|EINRI,|x|BEKAT)',
					@SQL_TableSourceCreateDate	='cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceUpDate		='cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceStornoDate	='cast(''31.12.2099 23:59:59'' as datetime)', @SQL_TableSourceStornoFlag='0',	
					@ValidToStorno	= 1, @ValidBeforeStorno = 0,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Behandlung_Kategorie_Text',
					@SQL_TableTargetID='|x|Behandlung_KategorieID',
					@SQL_TableSource_Where		= '|x|SPRAS=''D''',
					@SQL_TableTargetDefinition1 = '|x|BLTXT as KurzText',
					@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler 

Pre110:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Pre110'
			SET @StepText= Concat('','UpdateBaseTable [Bewegung_EntlassungZustand_Text]')

			--TN14W: Bewegung_EntlassungZustand_Text 00:00:08
			--Select * from replicate.sap.TN14W
			--Select * from Bewegung_EntlassungZustand_Text
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@CDPOS_laden=0,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='TN14W',
					@SQL_TableSourceFields='EZTXT',
					@SQL_TableSourceID='CONCAT(|x|MANDT,|x|EINRI,|x|ENTZU)',
					@SQL_TableSourceCreateDate	='cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceUpDate		='cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceStornoDate	='cast(''31.12.2099 23:59:59'' as datetime)', @SQL_TableSourceStornoFlag='0',	
					@ValidToStorno	= 1, @ValidBeforeStorno = 0,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Bewegung_EntlassungZustand_Text',
					@SQL_TableTargetID='|x|Bewegung_EntlassungZustandID',
					@SQL_TableSource_Where		= '|x|SPRAS=''D''',
					@SQL_TableTargetDefinition1 = 'EZTXT as KurzText',
					@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogStepError=@Fehler 

		end

	if @MainProcessing=1
		Begin
Main10:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Main10'
			SET @StepText= Concat('','UpdateBaseTable [Bewegungen_Aenderungshistorie]')

			SET @SQL_PostProcessing1=Concat('
				drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Falldaten_Fallzahlberechnung;
				Select Fallnummer
					, case when MAX(Bewegung_Aufnahme_ist_vorhanden)=1 and sum(Bewegung_Aufnahme_ist_nicht_storniert)=0 then 1 else 0 end Bewegung_Aufnahme_ist_storniert
					, case when MAX(Bewegung_Entlassung_ist_vorhanden)=1 and sum(Bewegung_Entlassung_ist_nicht_storniert)=0 then 1 else 0 end Bewegung_Entlassung_ist_storniert
					, max(Bewegung_Ambulant_ist_nicht_storniert) as Bewegung_Ambulant_ist_nicht_storniert
					, max(Bewegung_Teilstationäre_Aufnahme_ist_nicht_storniert) as Bewegung_Teilstationäre_Aufnahme_ist_nicht_storniert
					, max(Bewegung_Vorstationär_ist_nicht_storniert) as Bewegung_Vorstationär_ist_nicht_storniert
					, max(Bewegung_AOP_ist_nicht_storniert) as Bewegung_AOP_ist_nicht_storniert
					, max(Bewegung_ist_PruefVV_relevant) as Bewegung_ist_PruefVV_relevant
				into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Falldaten_Fallzahlberechnung
				from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Aenderungshistorie t1
				where Rang=1
				group by Fallnummer
				');

			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema, @TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen,
					@SQL_TableSourceName='NBEW',
					@SQL_TableSourceFields='MANDT,EINRI,FALNR,LFDNR,STATU,BETT,ZIMMR,KZTXT,ORGFA,ORGPF,ORGAU,BEWTY,BWART,BEKAT,BWGR1,BWGR2,PLANB,BWIDT,BWIZT,BWEDT,BWEZT,BWPDT,BWPZT,UNFKZ,EZUST',
					@SQL_TableSourceID='concat(|x|MANDT,|x|EINRI,|x|FALNR,|x|LFDNR)',
					@SQL_TableSourceCreateDate	='try_cast(|x|ERDAT as datetime)+try_cast(|x|ERTIM as datetime)',
					@SQL_TableSourceUpDate		='case when try_cast(|x|UPDAT as datetime)>0 then cast(|x|UPDAT as datetime) + cast(''00:00:00'' as datetime) else try_cast(|x|ERDAT as datetime)+try_cast(|x|ERTIM as datetime) end',
					@SQL_TableSourceStornoDate	='case when |x|STORN=''X'' and try_cast(|x|STDAT as datetime) >0 then cast(|x|STDAT as datetime) + cast(''23:59:59'' as datetime) else cast(''31.12.2099 23:59:59'' as datetime) end', 
					@SQL_TableSourceStornoFlag='case when |x|STORN=''X'' then 1 else 0 end',	@SQL_TableSourceStornoField = '|x|STORN',
					@SQL_TableSource_Join		= ' join Filter_Fallnummer tFilter on try_cast(|x|FALNR as bigint)=tFilter.FALNR',
					@SQL_TableSource_Where		= @SQL_TableSource_Where,
					@ValidToStorno	= @ValidToStorno, @ValidBeforeStorno = @ValidBeforeStorno, 
					@CDPOS_laden=@CDPOS_laden, @CDPOS_TableID= '|x|TABKEY',
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Bewegungen_Aenderungshistorie',
					@SQL_TableTargetID='|x|BewegungID',
					@SQL_TableTargetDefinition1=	'
	concat(|x|MANDT,|x|EINRI,|x|FALNR)			as FallID
	,cast(|x|FALNR as bigint)					as Fallnummer
	,cast(|x|LFDNR as int)						as Bewegung_Nummer

	,case when len(trim(|x|BWGR1))>0 then |x|BWGR1 else Null end								as Bewegung_Grund1
	,case when len(trim(|x|BWGR1))>0 then CONCAT(|x|MANDT,|x|BEWTY,1,|x|BWGR1) else Null end	as Bewegung_Grund1ID
	,case when len(trim(|x|BWGR2))>0 then |x|BWGR2 else Null end								as Bewegung_Grund2
	,case when len(trim(|x|BWGR2))>0 then CONCAT(|x|MANDT,|x|BEWTY,3,|x|BWGR2) else Null end	as Bewegung_Grund2ID

	,|x|BEWTY									as Bewegung_Typ 
	,concat(|x|MANDT,|x|EINRI,|x|BEWTY)			as Bewegung_TypID
	,cast(|x|STATU as int)						as Bewegung_Status

	,cast(case when len(trim(|x|BWART))>0 then |x|BWART else Null end as varchar(5))				as Bewegung_Art
	,case when len(trim(|x|BWART))>0 then concat(|x|MANDT,|x|EINRI,|x|BEWTY,|x|BWART) else Null end as Bewegung_ArtID

	,cast(case when len(trim(|x|BEKAT))>0 then |x|BEKAT else Null end as varchar(10))		as Behandlung_Kategorie
	,case when len(trim(|x|BEKAT))>0 then concat(|x|MANDT,|x|EINRI,|x|BEKAT) else Null end	as Behandlung_KategorieID

	,case when |x|BEWTY=2 and (|x|BEKAT like ''%PEP%'' or |x|ORGFA like ''PSY%'' or |x|ORGFA like ''KJP%'') then ''PEPP''
		  when |x|BEWTY=2 then ''DRG''
		  Else Null end							as Entgeltsystem

	,case when |x|BEWTY=2 and (|x|BEKAT like ''%PEP%'' or |x|ORGFA like ''PSY%'' or |x|ORGFA like ''KJP%'') then 1
		  when |x|BEWTY=2 then 0
		  Else 0 end							as Entgeltsystem_ist_PEPP

	,case when |x|BEWTY=2 and (|x|BEKAT like ''%PEP%'' or |x|ORGFA like ''PSY%'' or |x|ORGFA like ''KJP%'') then 0
		  when |x|BEWTY=2 then 1
		  Else 0 end							as Entgeltsystem_ist_DRG

	,cast(case when len(trim(|x|BETT))>0 then  |x|BETT else Null end as varchar(10))	as BettID
	,cast(case when len(trim(|x|ZIMMR))>0 then |x|ZIMMR else Null end as varchar(5))	as ZimmerID
	,cast(case when len(trim(|x|KZTXT))>0 then |x|KZTXT else Null end as varchar(50))	as KurzText

	,concat(|x|MANDT,|x|EINRI,|x|ORGPF)				as OrganisationISH_PflegeID
	,cast(case when len(trim(|x|ORGAU))>0 then concat(|x|MANDT,|x|EINRI,|x|ORGAU) else Null end as nvarchar(15)) as OrganisationISH_AufnahmeID
	,concat(|x|MANDT,|x|EINRI,|x|ORGFA)				as OrganisationISH_FachID
	,concat(|x|MANDT,|x|ORGFA,|x|ORGPF)				as OrganisationISH_FachPflegeID
	,concat(|x|MANDT,|x|ORGFA,''*'')				as OrganisationISH_FachSternID

	,case when len(trim(|x|UNFKZ))>0 then |x|UNFKZ else Null end							as Unfallkennzeichen
	,case when len(trim(|x|UNFKZ))>0 then concat(|x|MANDT,|x|EINRI,|x|UNFKZ) else Null end	as UnfallkennzeichenID

	,case when len(trim(|x|EZUST))>0 then |x|EZUST else Null end							as Entlassungszustand
	,case when len(trim(|x|EZUST))>0 then concat(|x|MANDT,|x|EINRI,|x|EZUST) else Null end	as EntlassungszustandID

	,try_cast(|x|BWIDT as datetime)+try_cast(|x|BWIZT as datetime)														as Bewegung_Beginn
	,case when year(|x|BWEDT)<>9999 then try_cast(|x|BWEDT as datetime)+try_cast(|x|BWEZT as datetime) else Null end	as Bewegung_Ende
	,case when year(|x|BWEDT)=9999 then 1 else 0 end																	as Bewegung_Ende_ist_unbekannt

	,case when year(|x|BWEDT)<>9999 then DATEDIFF(hour,try_cast(|x|BWIDT as datetime)+try_cast(|x|BWIZT as datetime), try_cast(|x|BWEDT as datetime)+try_cast(|x|BWEZT as datetime)) else Null	end as Bewegung_Dauer_Stunden
	,case when year(|x|BWEDT)<>9999 then DATEDIFF(d,try_cast(|x|BWIDT as datetime)+try_cast(|x|BWIZT as datetime), try_cast(|x|BWEDT as datetime)+try_cast(|x|BWEZT as datetime)) else Null	end		as Bewegung_Dauer_Tage

	,case when |x|PLANB=''P'' then 1 else 0 end						as Bewegung_ist_geplant
	,try_cast(|x|BWPDT as datetime)+try_cast(|x|BWPZT as datetime)	as Bewegung_ist_geplant_am

	,Case when |x|BEWTY =1 then 1 else 0 end															as Bewegung_Aufnahme_ist_vorhanden
	,Case when |x|BEWTY =2 then 1 else 0 end															as Bewegung_Entlassung_ist_vorhanden
	,Case when |x|BEWTY =1 and |x|Datensatz_ist_storniert=1 then 1 else 0 end										as Bewegung_Aufnahme_ist_nicht_storniert
	,Case when |x|BEWTY =2 and |x|Datensatz_ist_storniert=1 then 1 else 0 end										as Bewegung_Entlassung_ist_nicht_storniert
	,Case when |x|BEWTY =4 and |x|BWART not in (''VB'',''AO'') and |x|Datensatz_ist_storniert=1 then 1 else 0 end	as Bewegung_Ambulant_ist_nicht_storniert
	,Case when |x|BEWTY =1 and |x|BWGR1=3 and |x|Datensatz_ist_storniert=1 then 1 else 0 end							as Bewegung_Teilstationäre_Aufnahme_ist_nicht_storniert
	,Case when |x|BWART=''VB'' and |x|Datensatz_ist_storniert=1 then 1 else 0 end									as Bewegung_Vorstationär_ist_nicht_storniert
	,Case when |x|BWART=''AO'' and |x|Datensatz_ist_storniert=1 then 1 else 0 end									as Bewegung_AOP_ist_nicht_storniert
	,Case when |x|BEWTY =1 and |x|BWGR1 in (''01'',''02'',''08'') then 1 else 0 end						as Bewegung_ist_PruefVV_relevant
	',@SQL_PostProcessing1=@SQL_PostProcessing1
					
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='MainProcessing', @LogStepError=@Fehler 

		end

	if @PostProcessing=1
		begin
Post10:		
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post10'
			SET @StepText= Concat('','TabJoin [Bewegungen_BasisCube]')

			--Join: Bewegungen_BasisCube 00:21:26
			--Select * from Bewegungen_BasisCube where FallID='10000010020063404' and Bewegung_Typ=1
			--Declare @TEMPPraefix as nvarchar(100); Declare @TEMPLoeschen as int; Declare @SQL_TableTargetDB as nvarchar(200); Declare @SQL_TableTargetSchema as nvarchar(200); Declare @SQL as nvarchar(max); Declare @SQL1 as nvarchar(max); Declare @SQL2 as nvarchar(max); Set @SQL_TableTargetDB='Analysen'; Set @SQL_TableTargetSchema='dbo'; Set @TEMPLoeschen=0; Set @TEMPPraefix=62944979
			SET @SQL=concat('
				join (Select distinct FallID
					  from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Aenderungshistorie
					  where Bewegung_Typ in (1) and Bewegung_ist_geplant=0 and Datensatz_ist_storniert=0 and Rang=1
					  ) t2 on t1.FallID=t2.FallID 
				left join (Select distinct FallID, 1 as Fall_ist_entlassen
					  from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Aenderungshistorie
					  where Bewegung_Typ in (2) and Bewegung_Ende_ist_unbekannt=0 and Bewegung_ist_geplant=0 and Datensatz_ist_storniert=0 and Rang=1
					  ) t3 on t2.FallID=t3.FallID ')

			Execute [dbo].[TabJoin]
				@TEMPLoeschen=@TEMPLoeschen, @TEMPPraefix=@TEMPPraefix, @SQL_TableTargetDB	=@SQL_TableTargetDB, @SQL_TableTargetSchema =@SQL_TableTargetSchema,
				@SQL_Table1_SourceName  ='Bewegungen_Aenderungshistorie',
				@SQL_Table1_SourceJoin	=@SQL,
				@SQL_Table1_SourceFields = 't3.Fall_ist_entlassen',
				--@SQL_Table1_SourceWhere ='|x|FallID in (''10000010018655249'','''')',--|x|Bewegung_Ende_ist_unbekannt=0 and |x|Bewegung_ist_geplant=0',-- and (|x|FallID in (''10000010018655249'',''10000010017706384'',''10000010011259480x'',''10000010010414678x'',''10000010019925899x'',''10000010017574336x'',''10000010017583017x'',''10000010010053620x'') or |x|BewegungID in (''1000001001125948000001x'',''10000010017574336x'',''10000010017523841x'',''10000010017583017x'',''10000010017613377x'',''10000010018028158x''))',
				@SQL_Table2_SourceName	='Fallzusammenfuehrung_Bewegung',		@SQL_Table1_Connect_ID2 ='|x|BewegungID',					@SQL_Table2_Connect_ID ='|x|BewegungID_Alt',				@SQL_TableTargetRowID2 ='|x|RowID_Fallzusammenfuehrung_Bewegung', @SQL_Use_Table2_ID=1,
				@SQL_Table2_SourceWhere ='|x|Bewegung_Typ_Split37=0 or (|x|Bewegung_Typ_Split37=1 and |x|Bewegung_Typ=3)',
				--@SQL_Table3_SourceName	='Falldaten_BasisCube',					@SQL_Table1_Connect_ID3 ='|x|FallID',						@SQL_Table3_Connect_ID ='|x|FallID',						@SQL_TableTargetRowID3 ='|x|RowID_Falldaten_BasisCube', 
				@SQL_Table4_SourceName	='Behandlung_Kategorie_Eigenschaften',	@SQL_Table1_Connect_ID4 ='|x|Behandlung_KategorieID',		@SQL_Table4_Connect_ID ='|x|Behandlung_KategorieID',		@SQL_TableTargetRowID4 ='|x|RowID_BeKat',	
				@SQL_Table5_SourceName	='Bewegung_Art_Text',					@SQL_Table1_Connect_ID5 ='|x|Bewegung_ArtID',				@SQL_Table5_Connect_ID ='|x|Bewegung_ArtID',				@SQL_TableTargetRowID5 ='|x|RowID_BewArt_Text',	
				@SQL_Table6_SourceName	='Bewegung_Art_Kennzeichen',			@SQL_Table1_Connect_ID6 ='|x|Bewegung_ArtID',				@SQL_Table6_Connect_ID ='|x|Bewegung_ArtID',				@SQL_TableTargetRowID6 ='|x|RowID_BewArt_Kennzeichen',	
				@SQL_Table7_SourceName	='Bewegung_UnfallArt_Text',				@SQL_Table1_Connect_ID7 ='|x|UnfallkennzeichenID',			@SQL_Table7_Connect_ID ='|x|Bewegung_UnfallArtID',			@SQL_TableTargetRowID7 ='|x|RowID_UnfallArt',	
				@SQL_Table8_SourceName	='Behandlung_Kategorie_Text',			@SQL_Table1_Connect_ID8 ='|x|Behandlung_KategorieID',		@SQL_Table8_Connect_ID ='|x|Behandlung_KategorieID',		@SQL_TableTargetRowID8 ='|x|RowID_BeKat_Tex',	
				@SQL_Table9_SourceName	='Bewegung_EntlassungZustand_Text',		@SQL_Table1_Connect_ID9 ='|x|EntlassungszustandID',			@SQL_Table9_Connect_ID ='|x|Bewegung_EntlassungZustandID',	@SQL_TableTargetRowID9 ='|x|RowID_EntlassungsZustand',	
				@SQL_Table10_SourceName ='OrganisationISH_BasisCube',			@SQL_Table1_Connect_ID10 ='|x|OrganisationISH_PflegeID',	@SQL_Table10_Connect_ID ='|x|OrganisationISH_ID',			@SQL_TableTargetRowID10 ='|x|RowID_OE_Pflege',	
				@SQL_Table11_SourceName ='Bewegung_Grund_Bezeichnung',			@SQL_Table1_Connect_ID11 ='|x|Bewegung_Grund1ID',			@SQL_Table11_Connect_ID ='|x|Bewegung_GrundID',				@SQL_TableTargetRowID11 ='|x|RowID_Bewegung_Grund1',
				@SQL_Table12_SourceName ='Bewegung_Grund_Bezeichnung',			@SQL_Table1_Connect_ID12 ='|x|Bewegung_Grund2ID',			@SQL_Table12_Connect_ID ='|x|Bewegung_GrundID',				@SQL_TableTargetRowID12 ='|x|RowID_Bewegung_Grund2',	
				@SQL_Table13_SourceName ='OrganisationISH_BasisCube',			@SQL_Table1_Connect_ID13 ='|x|OrganisationISH_FachID',		@SQL_Table13_Connect_ID ='|x|OrganisationISH_ID',			@SQL_TableTargetRowID13 ='|x|RowID_OE_Fach',	
				@SQL_Table14_SourceName ='OrganisationISH_Kostenstelle',		@SQL_Table1_Connect_ID14 ='|x|OrganisationISH_FachPflegeID',@SQL_Table14_Connect_ID ='|x|OrganisationISH_FachPflegeID',	@SQL_TableTargetRowID14 ='|x|RowID_Kostenstelle1',	
				@SQL_Table15_SourceName ='OrganisationISH_Kostenstelle',		@SQL_Table1_Connect_ID15 ='|x|OrganisationISH_FachSternID', @SQL_Table15_Connect_ID ='|x|OrganisationISH_FachPflegeID',	@SQL_TableTargetRowID15 ='|x|RowID_Kostenstelle2',	
				@SQL_TableTargetName	='Bewegungen_BasisCube',				@SQL_TableTargetID='BewegungID',
				@SQL_TableTargetDefinition1='
				t2.AbrechnungID 
				,isnull(t2.BewegungID, t1.BewegungID)   as BewegungID
				,t1.BewegungID as BewegungID_Alt
				,isnull(t2.FallID, t1.FallID)			as FallID
				,t1.FallID								as FallID_Alt
				,isnull(t2.Fallnummer, t1.Fallnummer)	as Fallnummer
				,t1.Fallnummer							as Fallnummer_Alt
				,isnull(t2.Bewegung_Nummer, t1.Bewegung_Nummer)	as Bewegung_Nummer
				,t1.Bewegung_Nummer							as Bewegung_Nummer_Alt
				,isnull(t2.Bewegung_Typ, t1.Bewegung_Typ)	as Bewegung_Typ
				,t1.Bewegung_Typ							as Bewegung_Typ_Alt
				,isnull(t2.Bewegung_Typ_Split37,0)	as Bewegung_Typ_Split37
				,Case when t2.Fall_ist_fuehrend=1		then 1
					  when t2.Fall_ist_fuehrend=0		then 2
					  when t2.Fallnummer is null		then 0 
				  end Bewegung_Zusammenfuehrung_Typ
				,Case when t2.Fall_ist_fuehrend=1	then ''Führender Abrechnungsfall''
					  when t2.Fall_ist_fuehrend=0	then ''Nicht führender Abrechnungsfall''
					  when t2.Fallnummer is null	then ''keine Fallzusammenführung''
				  end Bewegung_Zusammenfuehrung_Typ_Text
				,t2.Bewegung_ist_storniert as Bewegung_ist_storniert',
				@SQL_TableTargetDefinition2='
				,t1.Bewegung_Grund1, t11.KurzText as Bewegung_Grund1_KurzText, t1.Bewegung_Grund1ID,t1.Bewegung_Grund2, t12.KurzText as Bewegung_Grund2_KurzText, t1.Bewegung_Grund2ID
				,t1.Bewegung_Status
				,t1.Bewegung_Art,t5.KurzText as Bewegung_Art_KurzText,t1.Bewegung_ArtID
				,isnull(t6.Tod,0) as Tod
				,isnull(t6.Neugeboren,0) as Neugeboren
				,isnull(t6.Entbindung,0) as Entbindung
				,isnull(t6.Begleitung,0) as Begleitung
				,isnull(t6.Begleitung_Medizinisch,0) as Begleitung_Medizinisch
				,isnull(t6.AufnahmeKH,0) as AufnahmeKH
				,case when isnull(t2.Bewegung_Typ, t1.Bewegung_Typ)=2 and t1.Bewegung_Grund1=''06'' then 1 else isnull(t6.EntlassungKH,0) end as EntlassungKH
				,isnull(t6.Vorstationaer,0) as Vorstationaer
				,isnull(t6.Nachstationaer,0) as Nachstationaer
				,isnull(t6.Teilstationaer,0) as Teilstationaer
				,isnull(t6.AmbulanteOP,0) as AmbulanteOP
				,isnull(t6.Operation,0) as Operation
				,isnull(t6.Notfall,0) as Notfall
				,isnull(t6.StatistikSperre,0) as StatistikSperre
				,isnull(t6.KVSperre,0) as KVSperre
				,t1.Behandlung_Kategorie,t8.KurzText as Behandlung_Kategorie_KurzText, t1.Behandlung_KategorieID
				,t1.Entgeltsystem
				,t1.BettID,t1.ZimmerID,t1.KurzText as KurzInfo
				,t1.OrganisationISH_PflegeID,t1.OrganisationISH_AufnahmeID,t1.OrganisationISH_FachID,t1.OrganisationISH_FachPflegeID,t1.OrganisationISH_FachSternID
				,t1.Unfallkennzeichen,t1.UnfallkennzeichenID
				,t1.EntlassungsZustand,t9.KurzText as EntlassungZustand_KurzText, t1.EntlassungsZustandID
				,t1.Bewegung_Beginn,t1.Bewegung_Ende,t1.Bewegung_Ende_ist_unbekannt
				,t1.Bewegung_Dauer_Stunden,t1.Bewegung_Dauer_Tage
				,t1.Bewegung_ist_geplant,t1.Bewegung_ist_geplant_am
				,t1.Bewegung_Aufnahme_ist_vorhanden,t1.Bewegung_Entlassung_ist_vorhanden,t1.Bewegung_Aufnahme_ist_nicht_storniert
				,t1.Bewegung_Entlassung_ist_nicht_storniert,t1.Bewegung_Ambulant_ist_nicht_storniert,t1.Bewegung_Teilstationäre_Aufnahme_ist_nicht_storniert
				,t1.Bewegung_Vorstationär_ist_nicht_storniert,t1.Bewegung_AOP_ist_nicht_storniert,t1.Bewegung_ist_PruefVV_relevant
				,isnull(t14.Kostenstelle,t15.Kostenstelle) as Kostenstelle
				,isnull(t14.Kostenstelle_Zahlenwert,t15.Kostenstelle_Zahlenwert) as Kostenstelle_Zahlenwert
				,t13.Fachrichtung1 as OrganisationISH_Fachrichtung
				,isnull(t0.Fall_ist_entlassen,0) as Fall_ist_entlassen
				',
				@SQL_TableTargetWhere='|x|BewegungID is not null'

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

Post20:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post20'
			SET @StepText= Concat('','Index [xBewegungen_BasisCubeFallID] für Tabelle [',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_BasisCube]')

			SET @SQL = Concat('CREATE NONCLUSTERED INDEX xBewegungen_BasisCubeFallID ON ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_BasisCube (FallID ASC) ')

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post30:			
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post30'
			SET @StepText= Concat('','TabJoin [Bewegungen_xFall]')

			--Join: Bewegungen_xFall - Bewegungen_xFall, Falldaten_BasisCube 00:00:45
			--Select * from Bewegungen_xFall where FallID='10000010010053620' and bewegung_typ in (1,2); Select * from Bewegungen_xFall where FallID='10000010010053620'
			--Declare @TEMPPraefix as nvarchar(100); Declare @TEMPLoeschen as int; Declare @SQL_TableTargetDB as nvarchar(200); Declare @SQL_TableTargetSchema as nvarchar(200); Declare @SQL as nvarchar(max); Declare @SQL1 as nvarchar(max); Declare @SQL2 as nvarchar(max); Set @SQL_TableTargetDB='Analysen'; Set @SQL_TableTargetSchema='dbo'; Set @TEMPLoeschen=0; Set @TEMPPraefix=62944979
			Execute [dbo].[TabJoin]
				@TEMPLoeschen=@TEMPLoeschen, @TEMPPraefix=@TEMPPraefix, @SQL_TableTargetDB	=@SQL_TableTargetDB, @SQL_TableTargetSchema =@SQL_TableTargetSchema,
				@SQL_Table1_SourceName  ='Bewegungen_BasisCube',	@SQL_Table1_SourceWhere ='|x|Bewegung_ist_geplant=0',-- and FallID in (''10000010015563331'',''10000010015651823'',''10000010010053620x'')',
				@SQL_Table2_SourceName	='Falldaten_BasisCube',		@SQL_Table1_Connect_ID2 ='|x|FallID',	@SQL_Table2_Connect_ID ='|x|FallID',	@SQL_TableTargetRowID2 ='|x|RowID_Falldaten_BasisCube', @SQL_Table2_SourceWhere='|x|Fallzusammenfuehrung_Typ<>2', @SQL_Table2_SourceJoinTyp='INNER',
				@SQL_TableTargetName	='Bewegungen_xFall',		@SQL_TableTargetID='|x|BewegungID',
				@SQL_TableTargetDefinition1='
				t1.BewegungID, t1.FallID, t1.Fallnummer, t1.Bewegung_Nummer, t1.Bewegung_Typ_Split37
				,t1.Bewegung_Typ, t1.Behandlung_Kategorie, t1.Bewegung_Art, t1.Bewegung_Grund1, t1.Bewegung_Grund2
				,t1.Bewegung_Beginn, t1.Bewegung_Ende, t1.Bewegung_Ende_ist_unbekannt, t1.Bewegung_Dauer_Tage 
				,t1.OrganisationISH_FachID, t1.OrganisationISH_PflegeID, t1.OrganisationISH_Fachrichtung
				,t1.Entgeltsystem, t1.Tod, t1.Neugeboren, t1.Entbindung, t1.Begleitung, t1.Begleitung_Medizinisch
				,t1.AufnahmeKH, t1.EntlassungKH
				,t1.Vorstationaer, t1.Nachstationaer, t1.Teilstationaer, t1.AmbulanteOP, t1.Operation, t1.Notfall
				,t1.StatistikSperre,t1.KVSperre
				,isnull(t2.Fall_Tage_ohne_Berechnung_MD,0) as Fall_Tage_ohne_Berechnung_MD
				,isnull(t2.Fall_Tage_ohne_Berechnung_Pflege,0) as Fall_Tage_ohne_Berechnung_Pflege
				,t2.Fall_Art
				,t2.Fall_Behandlungskategorie
				,t2.Fall_Abrechnung_Kennzeichen
				,t2.Fall_hat_Statistiksperre
				,t2.Fall_hat_Fakturasperre
				,t2.Fall_hat_Status_nach_MD_Verfahren
				,t2.Fall_Status
				,t2.Fall_Typ
				,t2.Fall_Merkmal
				,t2.Fall_ist_Auslandsfall
				,t1.Fall_ist_entlassen
				,t2.PatientenID'

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

Post40:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post40'
			SET @StepText= Concat('','Index [xBewegungen_xFall] für Tabelle [',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_xFall]')

			SET @SQL = Concat('CREATE NONCLUSTERED INDEX xBewegungen_xFall ON ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_xFall (FallID ASC) ')

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke

Post50:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post50'
			SET @StepText= Concat('','TabJoin [Bewegungen_AufnahmeEntlassung]')

			--Join: Bewegungen_AufnahmeEntlassung - Bewegungen_BasisCube,Bewegungen_xFall 00:02:23
			--Select * from Bewegungen_AufnahmeEntlassung where FallID='10000010018530790'  order by zeitraumid, bewegungid, rang
			--Select * from Bewegungen_xFall where FallID='10000010018530790'
			--Declare @TEMPPraefix as nvarchar(100); Declare @TEMPLoeschen as int; Declare @SQL_TableTargetDB as nvarchar(200); Declare @SQL_TableTargetSchema as nvarchar(200); Declare @SQL as nvarchar(max); Declare @SQL1 as nvarchar(max); Declare @SQL2 as nvarchar(max); Set @SQL_TableTargetDB='Analysen'; Set @SQL_TableTargetSchema='dbo'; Set @TEMPLoeschen=1; Set @TEMPPraefix=62944979
			Execute [dbo].[TabJoin]
				@TEMPLoeschen=@TEMPLoeschen, @TEMPPraefix=@TEMPPraefix, @SQL_TableTargetDB	=@SQL_TableTargetDB, @SQL_TableTargetSchema =@SQL_TableTargetSchema,
				@SQL_Table1_SourceName  ='Bewegungen_xFall', @SQL_TableTargetRowID1 ='|x|RowID_Bewegung', @SQL_Table1_ID ='|x|BewegungID',	
				@SQL_Table1_SourceWhere ='|x|Bewegung_Typ in (1,2,3,6,7) and isnull(|x|Begleitung,0)=0', -- and |x|FallID in (''10000010015563331'',''10000010015651823'',''10000010016375322'')',
				@SQL_Table2_SourceName	='Bewegungen_xFall',	@SQL_Table1_Connect_ID2 ='|x|FallID',	@SQL_Table2_Connect_ID ='|x|FallID',	@SQL_TableTargetRowID2 ='|x|RowID_Bewegung_Aufnahme', 
				@SQL_Table2_SourceWhere ='|x|Bewegung_Typ=1 and isnull(|x|Begleitung,0)=0',
				@SQL_Table3_SourceName	='Bewegungen_xFall',	@SQL_Table1_Connect_ID3 ='|x|FallID',	@SQL_Table3_Connect_ID ='|x|FallID',	@SQL_TableTargetRowID3 ='|x|RowID_Bewegung_Entlassung',	
				@SQL_Table3_SourceWhere ='|x|Bewegung_Typ=2 and isnull(|x|Begleitung,0)=0',
				@SQL_TableTargetName	='Bewegungen_AufnahmeEntlassung', @SQL_TableTargetID='|x|BewegungID',
				@SQL_TableTargetDefinition1='
				t1.FallID
				,DENSE_RANK() over (partition by t1.FallID order by t2.RowID, isnull(t3.RowID,0)) as ZeitraumID
				,t1.BewegungID
				,t1.Fallnummer
				,t1.Bewegung_Nummer

				,t2.BewegungID					as AufnahmeID
				,t2.Bewegung_Beginn				as Aufnahme_am
				,t2.Bewegung_Grund1				as Aufnahme_Grund1
				,t2.Bewegung_Grund2				as Aufnahme_Grund2
				,t2.OrganisationISH_FachID		as Aufnahme_OE_Fach_ID
				,t2.OrganisationISH_PflegeID	as Aufnahme_OE_Pflege_ID
				,t2.OrganisationISH_Fachrichtung as Aufnahme_OE_Fachrichtung 
				,t2.Behandlung_Kategorie		as Aufnahme_Behandlung_Kategorie
				,t2.Bewegung_Art				as Aufnahme_Art

				,isnull(t3.BewegungID, First_Value(t1.BewegungID) over (partition by t1.FallID,t2.RowID order by t1.Bewegung_Ende DESC, t2.Datensatz_gueltig_bis DESC)) as EntlassungID
				,isnull(isnull(t3.Bewegung_Ende, t3.Bewegung_Beginn), max(t1.Bewegung_Ende) over (partition by t1.FallID,t2.RowID )) as Entlassung_am
				,t3.Bewegung_Grund1				as Entlassung_Grund1
				,t3.Bewegung_Grund2				as Entlassung_Grund2
				,t3.OrganisationISH_FachID		as Entlassung_OE_Fach_ID
				,t3.OrganisationISH_PflegeID	as Entlassung_OE_Pflege_ID
				,t3.OrganisationISH_Fachrichtung as Entlassung_OE_Fachrichtung 
				,t3.Behandlung_Kategorie		as Entlassung_Behandlung_Kategorie
				,isnull(t3.Bewegung_Art, ''L'')	as Entlassung_Art
				,isnull(t3.Bewegung_Ende_ist_unbekannt,1) as Entlassung_unbekannt

				,datediff(d,t2.Bewegung_Beginn,isnull(isnull(t3.Bewegung_Ende, t3.Bewegung_Beginn), case when t2.Datensatz_gueltig_bis>getdate() or t1.Fall_ist_entlassen=0 then getdate() else cast(t2.Datensatz_gueltig_bis as datetime)+cast(''12:00:00'' as datetime)  end)) as Behandlungsdauer_in_Tagen
				,case when datediff(d,cast(t2.Bewegung_Beginn as date),cast(isnull(isnull(t3.Bewegung_Ende, t3.Bewegung_Beginn), case when t2.Datensatz_gueltig_bis>getdate() or t1.Fall_ist_entlassen=0 then getdate() else cast(t2.Datensatz_gueltig_bis as datetime)+cast(''12:00:00'' as datetime)  end) as date))=0 then 1 else 0 end as TagesAbrechnung',
					
				@SQL_TableTargetDefinition2='
				,t1.Bewegung_Typ,t1.Bewegung_Typ_Split37,t1.Bewegung_Art,t1.Behandlung_Kategorie,t1.Entgeltsystem,t1.Bewegung_Grund1,t1.Bewegung_Grund2
				,t1.Tod,t1.Neugeboren,t1.Entbindung,t1.Begleitung,t1.Begleitung_Medizinisch,t1.AufnahmeKH,t1.EntlassungKH,t1.Vorstationaer,t1.Nachstationaer,t1.Teilstationaer,t1.AmbulanteOP,t1.Operation,t1.Notfall,t1.StatistikSperre,t1.KVSperre,t1.OrganisationISH_Fachrichtung
				,t1.Bewegung_Beginn,t1.Bewegung_Ende
				,t1.Bewegung_Dauer_Tage
				,Lead(t1.Bewegung_Nummer) over (partition by t1.FallID order by t1.Bewegung_Nummer) as Nachfolger_Bewegung_Nummer

				,t1.Fall_Tage_ohne_Berechnung_MD
				,t1.Fall_Tage_ohne_Berechnung_Pflege
				,t1.Fall_Art
				,t1.Fall_Behandlungskategorie
				,t1.Fall_Abrechnung_Kennzeichen
				,t1.Fall_hat_Statistiksperre
				,t1.Fall_hat_Fakturasperre
				,t1.Fall_hat_Status_nach_MD_Verfahren
				,t1.Fall_ist_Auslandsfall
				,t1.Fall_Status
				,t1.Fall_Typ
				,t1.Fall_Merkmal
				,t1.PatientenID

				,case when t3.RowID is null then 0 else 1 end as Fall_ist_entlassen', 
				@SQL_TableTargetWhere='t1.RowID>0'

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

Post60:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post60'
			SET @StepText= Concat('','Erstellen der Tabelle [Bewegungen_AufnahmeEntlassung_Zeitscheiben]')

			Set @SQL = Concat('
			DROP TABLE if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung_Zeitscheiben;

			Select distinct FallID, Zeitstempel 
			into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung_Zeitscheiben
			from 
			(
				Select FallID, Datensatz_gueltig_von as Zeitstempel from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung where Datensatz_gueltig_von is not null
				union
				Select FallID, dateadd(d,1,Datensatz_gueltig_bis) as Zeitstempel from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung where Datensatz_gueltig_bis is not null and year(Datensatz_gueltig_bis)<2099
			) t
			where Zeitstempel is not null

			CREATE CLUSTERED INDEX xBewegungen_AufnahmeEntlassung_Zeitscheiben ON ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung_Zeitscheiben ( FallID, Zeitstempel ) 
			')

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke

Post70:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post70'
			SET @StepText= Concat('','Erstellen der Tabelle [Bewegungen_AufnahmeEntlassung0]')

			Set @SQL = Concat('
			DROP TABLE if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung0 ;

			select	 t2.RowID as RowID_Bewegungen_AufnahmeEntlassung
					,t2.RowID_Bewegung
					,t2.FallID, t3.ZeitraumID2 as ZeitraumID
					,t2.Bewegung_Nummer, t2.Bewegung_Typ, t2.Bewegung_Beginn, t2.Bewegung_Ende, t2.Bewegung_Dauer_Tage, t2.Behandlungsdauer_in_Tagen, t2.TagesAbrechnung
					,t2.Bewegung_Grund1, t2.Bewegung_Grund2, t2.Bewegung_Art, t2.AufnahmeKH as Bewegung_Aufnahme_externes_KH
					,t2.Bewegung_Typ_Split37,t2.Behandlung_Kategorie,t2.Entgeltsystem
					,t2.EntlassungKH as Bewegung_Entlassung_externes_KH
					,t2.Aufnahme_am, t2.Aufnahme_Grund1, t2.Aufnahme_Grund2, t2.Aufnahme_Art
					,t2.Entlassung_am, t2.Entlassung_Grund1, t2.Entlassung_Grund2, t2.Entlassung_Art
					,t2.Fall_Tage_ohne_Berechnung_MD, t2.Fall_Tage_ohne_Berechnung_Pflege					
					,t2.Tod,t2.Neugeboren,t2.Entbindung,t2.Begleitung,t2.Begleitung_Medizinisch,t2.AufnahmeKH,t2.EntlassungKH,t2.Vorstationaer,t2.Nachstationaer,t2.Teilstationaer,t2.AmbulanteOP,t2.Operation,t2.Notfall,t2.StatistikSperre,t2.KVSperre,t2.OrganisationISH_Fachrichtung
					,t2.Fall_Merkmal
					,t1.Zeitstempel as Datensatz_gueltig_von
					,case when t3.Datensatz_gueltig_bis>t2.Datensatz_gueltig_bis then t2.Datensatz_gueltig_bis else t3.Datensatz_gueltig_bis end as Datensatz_gueltig_bis
			into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung0
			from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung_Zeitscheiben t1
			 left join ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung t2 on t1.FallID=t2.FallID and t1.Zeitstempel between t2.Datensatz_gueltig_von and t2.Datensatz_gueltig_bis 
			 join (Select FallID, Zeitstempel as Datensatz_gueltig_von, Row_Number() over (partition by FallID order by Zeitstempel DESC) as ZeitraumID2
						  ,isnull(dateadd(d,-1,Lead(Zeitstempel) over (partition by FallID order by Zeitstempel)),cast(''31.12.2099'' as date)) as Datensatz_gueltig_bis
				   from (Select distinct FallID, Zeitstempel from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung_Zeitscheiben) t
				   ) t3 on t1.FallID=t3.FallID and t1.Zeitstempel = t3.Datensatz_gueltig_von
 
			CREATE NONCLUSTERED INDEX xBewegungen_AufnahmeEntlassung0 ON ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung0 ( FallID, ZeitraumID, Bewegung_Nummer, Bewegung_Typ ) 
			')

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke

Post80:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post80'
			SET @StepText= Concat('','Erstellen der Tabelle [Bewegungen_AufnahmeEntlassung_Cursor]')

			Set @SQL = Concat('
			DROP TABLE if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung_Cursor ;

			Select Distinct FallID, ZeitraumID, Bewegung_Nummer, Bewegung_Typ, Bewegung_Beginn_Max
				,Row_Number() over (partition by FallID, ZeitraumID order by Bewegung_Beginn_Max DESC, Bewegung_Nummer) as ID
				,Lead(Bewegung_Nummer) over (partition by FallID, ZeitraumID order by Bewegung_Beginn_Max, Bewegung_Nummer)																									as Nachfolger_Bewegung_Nummer
				,isnull(datediff(d,lag(Bewegung_Ende_Max) over (partition by FallID, ZeitraumID order by Bewegung_Beginn_Max, Bewegung_Typ DESC),Bewegung_Beginn_Max),0)													as Vorgaenger_Bewegung_Ende
				,Max(case when Bewegung_Typ <>6 then Bewegung_Ende_Max else Null end)  over (partition by FallID, ZeitraumID order by Bewegung_Beginn_Max, Bewegung_Typ ROWS between UNBOUNDED PRECEDING and 1 PRECEDING)	as Vorgaenger_Bewegung_Ende_ohneT6
				,Min(case when Bewegung_Typ <>6 then Bewegung_Beginn_Max else Null end)  over (partition by FallID, ZeitraumID order by Bewegung_Beginn_Max, Bewegung_Typ ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING) as Nachfolger_Bewegung_Beginn_ohneT6
			into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung_Cursor
			from (
				Select FallID, ZeitraumID, Bewegung_Nummer, Bewegung_Typ, max(Bewegung_Ende) as Bewegung_Ende_Max, max(Bewegung_Beginn) as Bewegung_Beginn_Max  
				from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung0 
				where Bewegung_Typ in (1,2,3,6,7) and not (Bewegung_Typ_Split37=1 and Bewegung_Typ=7)
				group by FallID, ZeitraumID, Bewegung_Nummer, Bewegung_Typ
				) t

			CREATE NONCLUSTERED INDEX xBewegungen_AufnahmeEntlassung_Cursor ON ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung_Cursor ( FallID, ZeitraumID, Bewegung_Nummer, Bewegung_Typ )
			')

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke

Post90:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post90'
			SET @StepText= Concat('','Erstellen der Tabelle [Bewegungen_AufnahmeEntlassung_Group]')

			Set @SQL = Concat('
			DROP TABLE if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung_Group ;

			Select FallID,ZeitraumID
				,MAX(case when Entgeltsystem=''PEPP'' then 1 else 0 end) as PEPP
				,Max(case when Entgeltsystem=''DRG'' then 1 else 0 end) as DRG
				,MAX(Tod)				as Fall_Bewegung_Tod
				,MAX(Neugeboren)		as Fall_Bewegung_Neugeboren
				,MAX(Entbindung)		as Fall_Bewegung_Entbindung
				,MAX(Begleitung)		as Fall_Bewegung_Begleitung
				,MAX(Begleitung_Medizinisch) as Fall_Bewegung_Begleitung_Medizinisch
				,MAX(AufnahmeKH)		as Fall_Bewegung_AufnahmeKH
				,MAX(EntlassungKH)		as Fall_Bewegung_EntlassungKH
				,MAX(Vorstationaer)		as Fall_Bewegung_Vorstationaer
				,MAX(Nachstationaer)	as Fall_Bewegung_Nachstationaer
				,MAX(Teilstationaer)	as Fall_Bewegung_Teilstationaer
				,MAX(AmbulanteOP)		as Fall_Bewegung_AmbulanteOP
				,MAX(Operation)			as Fall_Bewegung_Operation
				,MAX(Notfall)			as Fall_Bewegung_Notfall
				,MAX(Fall_Merkmal)		as Fall_Merkmal
			into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung_Group 
			from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung0
			group by FallID,ZeitraumID

			CREATE CLUSTERED INDEX xBewegungen_AufnahmeEntlassung_Group ON ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung_Group
			( FallID, ZeitraumID ) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
			')

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post100:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post100'
			SET @StepText= Concat('','Erstellen der Tabelle [Bewegungen_AufnahmeEntlassung_Gueltigkeit]')

			Set @SQL = Concat('
			DROP TABLE if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung_Gueltigkeit ;

			Select FallID, Bewegung_Nummer, Datensatz_gueltig_von, ZeitraumID
				,isnull(dateadd(d,-1,lead(Datensatz_gueltig_von) over (partition by FallID, ZeitraumID,Bewegung_Nummer order by Datensatz_gueltig_von)), Datensatz_gueltig_bis) as Datensatz_gueltig_bis
			into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung_Gueltigkeit
			from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung0

			CREATE NONCLUSTERED INDEX xBewegungen_AufnahmeEntlassung_Gueltigkeit ON ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung_Gueltigkeit (FallID, Bewegung_Nummer, Datensatz_gueltig_von ) 
			')

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post110:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post110'
			SET @StepText= Concat('','Erstellen der Tabelle [Bewegungen_AufnahmeEntlassung1]')

			Set @SQL = Concat('
			drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung1

			Select	distinct
					t1.RowID_Bewegungen_AufnahmeEntlassung, t1.FallID, t1.ZeitraumID, t1.Bewegung_Nummer, t1.Bewegung_Typ, t1.Bewegung_Beginn, t1.Bewegung_Ende, t1.Bewegung_Grund1, t1.Bewegung_Grund2, t1.Bewegung_Art, t1.AufnahmeKH as Bewegung_Aufnahme_externes_KH, t1.EntlassungKH as Bewegung_Entlassung_externes_KH
					,t1.Aufnahme_am, t1.Aufnahme_Grund1, t1.Aufnahme_Grund2, t1.Aufnahme_Art
					,t1.Entlassung_am, t1.Entlassung_Grund1, t1.Entlassung_Grund2, t1.Entlassung_Art
					,t1.Fall_Tage_ohne_Berechnung_MD, t1.Fall_Tage_ohne_Berechnung_Pflege
					,t3.Vorgaenger_Bewegung_Ende
					,t3.Nachfolger_Bewegung_Nummer
					,t3.Vorgaenger_Bewegung_Ende_ohneT6
					,t3.Nachfolger_Bewegung_Beginn_ohneT6
					,t3.ID
					,t2.PEPP,t2.DRG
					,t2.Fall_Bewegung_Tod,t2.Fall_Bewegung_Neugeboren,t2.Fall_Bewegung_Entbindung,t2.Fall_Bewegung_Begleitung,t2.Fall_Bewegung_Begleitung_Medizinisch,t2.Fall_Bewegung_AufnahmeKH,t2.Fall_Bewegung_EntlassungKH,t2.Fall_Bewegung_Vorstationaer,t2.Fall_Bewegung_Nachstationaer,t2.Fall_Bewegung_Teilstationaer,t2.Fall_Bewegung_AmbulanteOP,t2.Fall_Bewegung_Operation,t2.Fall_Bewegung_Notfall, t2.Fall_Merkmal
					,t1.Datensatz_gueltig_von
					,t4.Datensatz_gueltig_bis
			into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung1
			from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung0  t1
				left join ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung_Group  t2		on t1.FallID=t2.FallID and t1.ZeitraumID=t2.ZeitraumID
				left join ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung_Cursor t3		on t1.FallID=t3.FallID and t1.Bewegung_Nummer=t3.Bewegung_Nummer and t1.ZeitraumID=t3.ZeitraumID
				left join ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung_Gueltigkeit t4 on t1.FallID=t4.FallID and t1.Bewegung_Nummer=t4.Bewegung_Nummer and t1.ZeitraumID=t4.ZeitraumID and t1.Datensatz_gueltig_von between t4.Datensatz_gueltig_von and t4.Datensatz_gueltig_bis
			where t1.Bewegung_Typ in (1,2,3,6,7) and not (t1.Bewegung_Typ_Split37=1 and t1.Bewegung_Typ=7) and datediff(d,t1.Datensatz_gueltig_von, t4.Datensatz_gueltig_bis)>=0

			CREATE NONCLUSTERED INDEX xBewegungen_AufnahmeEntlassung1 ON ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung1 ( FallID, ZeitraumID, Bewegung_Nummer, Datensatz_gueltig_von ) 
			')

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post120:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post120'
			SET @StepText= Concat('','Erstellen der Tabelle [Bewegungen_AufnahmeEntlassung2]')

			Set @SQL = Concat('
			drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung2;

			with Zeit 
			as (
				Select 
					t1.*
					,Sum(case when t1.Vorgaenger_Bewegung_Ende<>0 or t1.Bewegung_Typ in (6,7) then 1 else 0 end ) over (partition by t1.FallID, t1.ZeitraumID order by t1.Bewegung_Beginn, t1.Bewegung_Typ ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) +1 as Zeitblock
					,t2.Bewegung_Entlassung_externes_KH as Nachfolger_Bewegung_Entlassung_externes_KH
					,case when t2.Bewegung_Typ in (2,6) then t2.Bewegung_Art else Null end as Nachfolger_Bewegung_Art
					,case when t2.Bewegung_Typ in (6) and datediff(d,cast(t2.Bewegung_Beginn as date),cast(t2.Bewegung_Ende as date)) = 0 then 1 else 0 end as Nachfolger_Bewegung_Dauer0
				from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung1 t1
				left join ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung1 t2 on  t1.FallID=t2.FallID and t1.ZeitraumID=t2.ZeitraumID and t1.Nachfolger_Bewegung_Nummer=t2.Bewegung_Nummer
				where t1.Vorgaenger_Bewegung_Ende>=0 
				),
			Zusammenfassung
			as (
				Select FallID, ZeitraumID, Zeitblock
					,Max(PEPP)								as Fall_PEPP
					,Max(DRG)								as Fall_DRG
					,Min(Aufnahme_am)						as Aufnahme_am
					,Max(Entlassung_am)						as Entlassung_am
					,Min(ID)								as Min_ID
					,Max(ID)								as Max_ID
					,Max(Fall_Tage_ohne_Berechnung_MD)		as Fall_Tage_ohne_Berechnung_MD
					,Max(Fall_Tage_ohne_Berechnung_Pflege)	as Fall_Tage_ohne_Berechnung_Pflege
					,Datensatz_gueltig_von, Datensatz_gueltig_bis
				From Zeit
				where Bewegung_Typ<>6
				group by FallID, ZeitraumID, Zeitblock, Datensatz_gueltig_von, Datensatz_gueltig_bis
			)
			--Select * from Zusammenfassung
			')

			Set @SQL1 = Concat('
			Select distinct
				t1.FallID, t1.ZeitraumID, t1.Zeitblock, t1.Fall_PEPP, t1.Fall_DRG
				,t2.Bewegung_Nummer		as BlockStart_Bewegung_Nummer
				,t2.Bewegung_Typ		as BlockStart_Bewegung_Typ
				,t2.Bewegung_Beginn		as BlockStart_Bewegung_Beginn_am
				,t2.Bewegung_Grund1		as BlockStart_Bewegung_Grund1
				,t2.Bewegung_Grund2		as BlockStart_Bewegung_Grund2
				,t2.Bewegung_Art		as BlockStart_Bewegung_Art

				,t2.Bewegung_Aufnahme_externes_KH	as BlockStart_Bewegung_Aufnahme_externes_KH
				,t2.Vorgaenger_Bewegung_Ende		as BlockStart_Vorgaenger_Bewegung_Ende

				,t3.Bewegung_Nummer		as BlockEnd_Bewegung_Nummer
				,t3.Bewegung_Typ		as BlockEnd_Bewegung_Typ
				,t3.Bewegung_Ende		as BlockEnd_Bewegung_Ende_am
				,t3.Bewegung_Grund1		as BlockEnd_Bewegung_Grund1
				,t3.Bewegung_Grund2		as BlockEnd_Bewegung_Grund2
				,t3.Bewegung_Art		as BlockEnd_Bewegung_Art

				,t2.Vorgaenger_Bewegung_Ende_ohneT6		as BlockStart_Vorgaenger_Bewegung_Ende_ohneT6
				,t3.Nachfolger_Bewegung_Beginn_ohneT6	as BlockEnd_Nachfolger_Bewegung_Beginn_ohneT6
				
				,isnull(t3.Nachfolger_Bewegung_Entlassung_externes_KH,t3.Bewegung_Entlassung_externes_KH)	as BlockEnd_Bewegung_Entlassung_externes_KH
				
				,t3.Nachfolger_Bewegung_Art						as BlockEnd_Nachfolger_Bewegung_Art
				,t3.Nachfolger_Bewegung_Dauer0					as BlockEnd_Nachfolger_Bewegung_Dauer0
				,t3.Nachfolger_Bewegung_Nummer					as BlockEnd_Nachfolger_Bewegung_Nummer

				,case when t3.Bewegung_Typ=2 then 1 else 0 end	as BlockEnd_Bewegung_ist_letzte_Bewegung

				,datediff(d,t2.Bewegung_Beginn, t3.Bewegung_Ende) as Block_Bewegung_Dauer
	
				,t1.Aufnahme_am			as Fall_Aufnahme_am
				,t2.Aufnahme_Grund1		as Fall_Aufnahme_Grund1
				,t2.Aufnahme_Grund2		as Fall_Aufnahme_Grund2
				,t2.Aufnahme_Art		as Fall_Aufnahme_Art
				,t1.Entlassung_am		as Fall_Entlassung_am
				,t3.Entlassung_Grund1	as Fall_Entlassung_Grund1
				,t3.Entlassung_Grund2	as Fall_Entlassung_Grund2
				,t3.Entlassung_Art		as Fall_Entlassung_Art

				,t2.Fall_Merkmal
				,t1.Fall_Tage_ohne_Berechnung_MD
				,t1.Fall_Tage_ohne_Berechnung_Pflege

				,t3.RowID_Bewegungen_AufnahmeEntlassung
				,t1.Datensatz_gueltig_von, t1.Datensatz_gueltig_bis
			into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung2
			From Zusammenfassung t1
			left join Zeit t2 on  t1.FallID=t2.FallID and t1.ZeitraumID=t2.ZeitraumID and t1.Zeitblock=t2.Zeitblock and t1.Max_ID=t2.ID
			left join Zeit t3 on  t1.FallID=t3.FallID and t1.ZeitraumID=t3.ZeitraumID and t1.Zeitblock=t3.Zeitblock and t1.Min_ID=t3.ID
			')

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post130:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post130'
			SET @StepText= Concat('','Erstellen der Tabelle [Bewegungen_AufnahmeEntlassung3]')

			Set @SQL = Concat('
			Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung3;
			Select FallID, ZeitraumID
				,BlockEnd_Bewegung_Nummer as Bewegung_Nummer
				,BlockStart_Bewegung_Beginn_am
				,BlockEnd_Bewegung_Ende_am
				,Block_Bewegung_Dauer
				,Fall_PEPP
				,Fall_DRG
				,Fall_Aufnahme_am
				,Fall_Entlassung_am
				,Fall_Merkmal
				,Fall_Tage_ohne_Berechnung_MD
				,Fall_Tage_ohne_Berechnung_Pflege
				,BlockStart_Bewegung_Aufnahme_externes_KH
				,BlockEnd_Bewegung_Entlassung_externes_KH
				,case when Fall_DRG=1 and BlockEnd_Bewegung_Entlassung_externes_KH=0 and BlockEnd_Bewegung_ist_letzte_Bewegung=0 and left(BlockEnd_Nachfolger_Bewegung_Art,1)<>''E'' and BlockEnd_Nachfolger_Bewegung_Dauer0=0 then 1 else 0 end as Tage1
				,case when Fall_DRG=1 and Fall_Aufnahme_Grund1=''03'' then 1 else 0 end as Tage2
				,case when Fall_DRG=1 and left(BlockEnd_Bewegung_Art,1)=''E'' and datediff(d,BlockStart_Bewegung_Beginn_am, BlockEnd_Bewegung_Ende_am)=0 and BlockStart_Vorgaenger_Bewegung_Ende>0 then 1 else 0 end as Tage3
				,case when Fall_DRG=1 and BlockEnd_Nachfolger_Bewegung_Dauer0=1 and left(BlockEnd_Nachfolger_Bewegung_Art,1)=''E'' and datediff(d,BlockStart_Bewegung_Beginn_am, BlockEnd_Bewegung_Ende_am)=0 then 1 else 0 end as Tage4
				,case when Fall_PEPP=1 and (BlockEnd_Nachfolger_Bewegung_Dauer0=0 or left(BlockEnd_Nachfolger_Bewegung_Art,1)=''E'') and Fall_Entlassung_Grund2 not in (17,22) then 1 else 0 end as Tage5
				,case when Fall_DRG=1 and CAST(BlockStart_Bewegung_Beginn_am as date)>CAST(BlockStart_Vorgaenger_Bewegung_Ende_ohneT6 as date) and BlockEnd_Bewegung_ist_letzte_Bewegung=1 and Block_Bewegung_Dauer=0 and BlockStart_Bewegung_Typ<>7 then 1 else 0 end as Tage6
				,case when datediff(d,Fall_Aufnahme_am,Fall_Entlassung_am)=0 then 1 else 0 end as Tage7
				,case when 
					(	 case when Fall_DRG=1 and BlockEnd_Bewegung_Entlassung_externes_KH=0 and BlockEnd_Bewegung_ist_letzte_Bewegung=0 and left(BlockEnd_Nachfolger_Bewegung_Art,1)<>''E'' and BlockEnd_Nachfolger_Bewegung_Dauer0=0 then 1 else 0 end
						+case when Fall_DRG=1 and Fall_Aufnahme_Grund1=''03'' then 1 else 0 end 
						+case when Fall_DRG=1 and left(BlockEnd_Bewegung_Art,1)=''E'' and datediff(d,BlockStart_Bewegung_Beginn_am, BlockEnd_Bewegung_Ende_am)=0 and BlockStart_Vorgaenger_Bewegung_Ende>0 then 1 else 0 end
						+case when Fall_DRG=1 and BlockEnd_Nachfolger_Bewegung_Dauer0=1 and left(BlockEnd_Nachfolger_Bewegung_Art,1)=''E'' and datediff(d,BlockStart_Bewegung_Beginn_am, BlockEnd_Bewegung_Ende_am)=0 then 1 else 0 end
						+case when Fall_PEPP=1 and (BlockEnd_Nachfolger_Bewegung_Dauer0=0 or left(BlockEnd_Nachfolger_Bewegung_Art,1)=''E'') and Fall_Entlassung_Grund2 not in (17,22) then 1 else 0 end
						+case when Fall_DRG=1 and CAST(BlockStart_Bewegung_Beginn_am as date)>CAST(BlockStart_Vorgaenger_Bewegung_Ende_ohneT6 as date) and BlockEnd_Bewegung_ist_letzte_Bewegung=1  and Block_Bewegung_Dauer=0 and BlockStart_Bewegung_Typ<>7 then 1 else 0 end
						+case when datediff(d,Fall_Aufnahme_am,Fall_Entlassung_am)=0 then 1 else 0 end
					) >0
				 then 1 else 0 end Belegungstage_letzter_Tag
				 ,BlockEnd_Nachfolger_Bewegung_Dauer0
				 ,RowID_Bewegungen_AufnahmeEntlassung
				 ,Datensatz_gueltig_von, Datensatz_gueltig_bis
			into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung3
			from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung2 t1
			')

			--Select * from Bewegungen_AufnahmeEntlassung3 where FallID in ('10000010016811174x','10000010017523841x','10000010018028158x','10000010018194075' ) and ZeitraumID=1
			--Select * from Bewegungen_AufnahmeEntlassung3 where FallID in ('10000010010053620','10000010017523841x','10000010018028158x','10000010018347223' ) and ZeitraumID=1
			--Select right(FallID,8) as Fallnummer, Verweildauer,* from Bewegungen_Verweildauer where  ZeitraumID=1 and year(Entlassung_am)=2023 and DRG=1 and FallID in ('10000010016811174x','10000010017523841x','10000010017771344x','10000010018076532' )

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post140:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post140'
			SET @StepText= Concat('','Erstellen der Tabelle [Bewegungen_AufnahmeEntlassung4]')

			Set @SQL = Concat('
			Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung4;
			Select FallID
				,Sum(Block_Bewegung_Dauer) as Behandlungstage
				,Sum(Block_Bewegung_Dauer+Belegungstage_letzter_Tag) as Belegungstage
				,Sum(Block_Bewegung_Dauer+Belegungstage_letzter_Tag)-max(Fall_Tage_ohne_Berechnung_MD) as Verweildauer
				,Max(Fall_Tage_ohne_Berechnung_MD) as Fall_Tage_ohne_Berechnung_MD
				,Max(Fall_Tage_ohne_Berechnung_Pflege) as Fall_Tage_ohne_Berechnung_Pflege
				,Max(BlockStart_Bewegung_Aufnahme_externes_KH) as Fall_Aufnahme_externes_KH
				,Max(BlockEnd_Bewegung_Entlassung_externes_KH) as Fall_Entlassung_externes_KH
				,Max(Fall_PEPP) as Fall_PEPP
				,Max(Fall_DRG) as Fall_DRG
				,Max(Fall_Merkmal) as Fall_Merkmal
				,Min(Fall_Aufnahme_am) as Fall_Aufnahme_am
				,Max(Fall_Entlassung_am) as Fall_Entlassung_am
				,cast(HASHBYTES(''SHA1'', (select 
							Sum(Block_Bewegung_Dauer+Belegungstage_letzter_Tag) as Belegungstage
							,Sum(Block_Bewegung_Dauer+Belegungstage_letzter_Tag)-max(Fall_Tage_ohne_Berechnung_MD) as Verweildauer
							,Max(Fall_Tage_ohne_Berechnung_MD) as Fall_Tage_ohne_Berechnung_MD
							,Max(Fall_Tage_ohne_Berechnung_Pflege) as Fall_Tage_ohne_Berechnung_Pflege
							,Max(BlockStart_Bewegung_Aufnahme_externes_KH) as Fall_Aufnahme_externes_KH
							,Max(BlockEnd_Bewegung_Entlassung_externes_KH) as Fall_Entlassung_externes_KH
						FOR XML RAW)) as varbinary(100)) as HashID
				,ZeitraumID as Rang
				,cast(cast(Datensatz_gueltig_von as date) as datetime) as Datensatz_gueltig_von
				,cast(cast(Datensatz_gueltig_bis as date) as datetime)+cast(''23:59:59'' as datetime) as Datensatz_gueltig_bis 
			into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung4
			from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung3
			group by FallID,ZeitraumID,Datensatz_gueltig_von,Datensatz_gueltig_bis
			')
			--Select * from Bewegungen_AufnahmeEntlassung4 where FallID in ('10000010016811174x','10000010017523841x','10000010018028158x','10000010017927118' ) 

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post150:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post150'
			SET @StepText= Concat('','Erstellen der Tabelle [Bewegungen_AufnahmeEntlassung5]')

			Set @SQL = Concat('
			Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung5;
			Select *
				,case when HashID=LAG(HashID) over (partition by FallID order by Datensatz_gueltig_von) 
					and DateAdd(s,1,LAG(Datensatz_gueltig_bis) over (partition by FallID order by Datensatz_gueltig_von))=Datensatz_gueltig_von 
					then 0 else 1 end ZeitSprung
			into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung5
			from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung4 
			')
			--Select * from Bewegungen_AufnahmeEntlassung5 where FallID in ('10000010016811174x','10000010017523841x','10000010018028158x','10000010017896610' ) 

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post160:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post160'
			SET @StepText= Concat('','Erstellen der Tabelle [Bewegungen_AufnahmeEntlassung6]')

			Set @SQL = Concat('
			Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung6;
			Select *
				,Sum(ZeitSprung) over (partition by FallID order by Rang DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)  as ZeitBlock
			into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung6
			from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung5 
			')
			--Select * from Bewegungen_AufnahmeEntlassung6 where FallID in ('10000010016811174x','10000010017523841x','10000010018028158x','10000010017230769' ) 

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post170:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post170'
			SET @StepText= Concat('','Erstellen der Tabelle [Bewegungen_Verweildauer]')

			Set @SQL = Concat('
			Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer;
			Select IDENTITY(BIGINT,1,1) AS RowID 
				,t1.FallID
				,t2.SchluesselID
				,Zeitblock
				,Max(Fall_PEPP) as PEPP
				,Max(Fall_DRG) as DRG
				,Min(Fall_Aufnahme_am) as Aufnahme_am
				,Max(Fall_Entlassung_am) as Entlassung_am
				,Max(Behandlungstage) as Behandlungstage
				,Max(Belegungstage) as Belegungstage
				,Max(Verweildauer) as Verweildauer
				,Max(Fall_Merkmal) as Fall_Merkmal
				,Max(Fall_Tage_ohne_Berechnung_MD)	   as Fall_Tage_ohne_Berechnung_MD
				,Max(Fall_Tage_ohne_Berechnung_Pflege) as Fall_Tage_ohne_Berechnung_Pflege
				,Max(Fall_Aufnahme_externes_KH) as AufnahmeKH
				,Max(Fall_Entlassung_externes_KH) as EntlassungKH
				,Min(Rang) as ZeitraumID
				,DENSE_RANK() over (partition by t1.FallID order by Min(Datensatz_gueltig_von) DESC) as Rang
				,1 as LastChangeOnDate
				,cast(Min(Datensatz_gueltig_von) as Date) as Datensatz_gueltig_von
				,cast(Max(Datensatz_gueltig_bis) as Date) as Datensatz_gueltig_bis 
			into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer
			from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung6 t1
				join (Select Distinct FallID, Row_Number() over (order by FallID) as SchluesselID 
					  from (
							Select Distinct FallID from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung6
							) t
					) t2 on t1.FallID=t2.FallID
			where Verweildauer is not null
			Group by t1.FallID, t1.Zeitblock,t2.SchluesselID

			CREATE UNIQUE NONCLUSTERED INDEX xFallID ON ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer (SchluesselID ASC, FallID ASC, Rang ASC, Datensatz_gueltig_von ASC) 
				
			ALTER TABLE ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer
			ADD CONSTRAINT PK_Bewegungen_Verweildauer_RowID PRIMARY KEY CLUSTERED (RowID);		
			')
			--Select * from Bewegungen_Verweildauer where FallID in ('10000010016811174x','10000010017523841x','10000010018028158x','10000010017230769' ) 

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post180:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post180'
			SET @StepText= Concat('','Update der Tabelle [Admin_TabTree]')

			Set @SQL = Concat('
			Delete ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_TabTree where TargetTableDB=''',@SQL_TableTargetDB,''' and TargetTableSchema=''',@SQL_TableTargetSchema,''' and TargetTableName=''Bewegungen_Verweildauer'';

			Insert into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_TabTree
			Values ((SELECT isnull(MAX(RelationID),1) + 1 FROM ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_TabTree),
			''',@SQL_TableTargetDB,''',
			''',@SQL_TableTargetSchema,''',
			''Bewegungen_Verweildauer'',
			(Select Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer'',''U'')),
			''FallID'',
			''RowID_AufnahmeEntlassung'',
			Getdate(),
			(SELECT max(p.rows) as Zeilen
									FROM sys.tables AS tbl
									JOIN sys.indexes as i ON i.object_id = tbl.object_id
									JOIN sys.partitions as p ON p.object_id = i.object_id and p.index_id = i.index_id
									JOIN sys.allocation_units as a ON a.container_id = p.partition_id
									where tbl.object_id=Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer'',''U'')),
			(SELECT ISNULL(8 * SUM(CASE WHEN a.type <> 1 THEN a.used_pages WHEN p.index_id < 2 THEN a.data_pages ELSE 0 END),0.0) as Speicherplatz
									FROM sys.tables AS tbl
									JOIN sys.indexes as i ON i.object_id = tbl.object_id
									JOIN sys.partitions as p ON p.object_id = i.object_id and p.index_id = i.index_id
									JOIN sys.allocation_units as a ON a.container_id = p.partition_id
									where tbl.object_id=Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer'',''U'')),
			''',@SQL_TableTargetDB,''',
			''',@SQL_TableTargetSchema,''',
			''Bewegungen_AufnahmeEntlassung'',
			(Select Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung'',''U'')),
			(Select Distinct TargetID from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_TabTree where TargetObjectID= Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung'',''U'')),
			''RowID'',
			(Select modify_date from ',@SQL_TableTargetDB,'.sys.tables where object_id=Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung'',''U'')),
			Null,
			Null,
			1,
			''valid'',
			''F'',
			0,
			''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_Log'')
			')

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post190:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post190'
			SET @StepText= Concat('','TabJoin [Bewegungen_AufnahmeEntlassung_xVerweildauer]')

			--Declare @TEMPPraefix as nvarchar(100); Declare @TEMPLoeschen as int; Declare @SQL_TableTargetDB as nvarchar(200); Declare @SQL_TableTargetSchema as nvarchar(200); Declare @SQL as nvarchar(max); Declare @SQL1 as nvarchar(max); Declare @SQL2 as nvarchar(max); Set @SQL_TableTargetDB='Analysen'; Set @SQL_TableTargetSchema='dbo'; Set @TEMPLoeschen=0; Set @TEMPPraefix=62944979
			Execute [dbo].[TabJoin]
				@MAxdelay=-1,@TEMPLoeschen=@TEMPLoeschen, @TEMPPraefix=@TEMPPraefix, @SQL_TableTargetDB	=@SQL_TableTargetDB, @SQL_TableTargetSchema =@SQL_TableTargetSchema,
				@SQL_Table1_SourceName  ='Bewegungen_AufnahmeEntlassung',		@SQL_TableTargetRowID1 ='|x|RowID_Bewegungen_AufnahmeEntlassung', --@SQL_Table1_SourceWhere ='|x|FallID=''10000010018500300''',
				@SQL_Table2_SourceName	='Bewegungen_Verweildauer',		@SQL_Table1_Connect_ID2 ='|x|FallID',	@SQL_Table2_Connect_ID ='|x|FallID',	@SQL_TableTargetRowID2 ='|x|RowID_Verweildauer', 
				@SQL_TableTargetName	='Bewegungen_AufnahmeEntlassung_xVerweildauer', @SQL_TableTargetID='|x|BewegungID',
				@SQL_TableTargetDefinition1='t1.FallID, t1.BewegungID, t1.Bewegung_Nummer, t1.Bewegung_Typ, t1.Bewegung_Beginn, t1.Bewegung_Ende, t2.Aufnahme_am, t2.Entlassung_am, t2.Verweildauer, t1.Rang as Rang_AufnahmeEntlassung',			
				@SQL_TableTargetWhere='t2.RowID>0'
			/*
			
				Select distinct t1.FallID,t2.Fallnummer, t1.PEPP,t1.DRG,t1.Belegungstage,t1.Fall_Tage_ohne_Berechnung_MD,t1.Verweildauer,t2.Belegungstage, t2.Gesamt
			from Analysen.dbo.Bewegungen_Verweildauer t1
			 join [dbo].[DRGView] t2 on right(t1.FallID,8)=t2.Fallnummer and t1.Rang=1 and t2.Belegungstage<>t1.Belegungstage 
			where t1.FallID in ('10000010018205375x','10000010010053620','10000010017669497x','10000010018050251x','10000010018222988x','10000010017674972' ) 

			*/

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post200:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post200'
			SET @StepText= Concat('','Erstellen der Tabelle [Bewegungen_Verweildauer_PEPP_Monat_Temp1]')

			Set @SQL = Concat('
			Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat_Temp1;
			WITH 
			Kalender
				as (SELECT   CAST(concat(''01.01.'',year(getdate())-6) AS DATETIME) AS Tag
					UNION ALL         
					SELECT   DATEADD(m, 1, Tag)
					FROM     Kalender
					WHERE    DATEADD(m, 1, Tag ) <= Getdate()),
			Monate
				as (Select cast(convert(varchar(10), Tag, 104) as datetime) as von, cast(convert(varchar(10), EOMONTH(Tag), 104) as datetime) + cast(''23:59:59'' as datetime) as bis
					from Kalender),
			Aufteilung
				as (Select t2.FallID,t2.ZeitraumID, t3.RowID as RowID_Bewegungen_Verweildauer
						,case when t2.BlockStart_Bewegung_Beginn_am	<=t1.von then t1.von else t2.BlockStart_Bewegung_Beginn_am	end as Bewegung_Beginn
						,case when t2.BlockEnd_Bewegung_Ende_am	>=t1.bis then t1.bis else t2.BlockEnd_Bewegung_Ende_am		end as Bewegung_Ende
						,case when t2.BlockEnd_Bewegung_Ende_am	between t1.von and t1.bis then t2.Belegungstage_letzter_Tag else 0 end 
						 +case when t2.BlockEnd_Bewegung_Ende_am	>=t1.bis then 1 else 0		end as Belegungstage_letzter_Tag
						,concat(year(t1.von),''-'',Month(t1.von))						as Kalkulationsmonat
						,cast(concat(''1.'',Month(t1.von),''.'',year(t1.von)) as datetime)	as Kalkulationsmonat_von
						,cast(EOMONTH(t1.von) as datetime)+cast(''23:59:59'' as datetime)	as Kalkulationsmonat_bis
						,case when t2.BlockEnd_Bewegung_Ende_am = t3.Entlassung_am then t2.Fall_Tage_ohne_Berechnung_MD else 0 end Fall_Tage_ohne_Berechnung_MD
						,t3.Verweildauer
						,t2.Fall_Aufnahme_am
						,t2.Datensatz_gueltig_von, t2.Datensatz_gueltig_bis
					from Monate t1
							left join ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung3 t2 on    (cast(BlockStart_Bewegung_Beginn_am as date) < t1.von and cast(BlockEnd_Bewegung_Ende_am as date) > t1.von) 
																			   or cast(BlockStart_Bewegung_Beginn_am as date) between t1.von and t1.bis   
																			   or cast(BlockEnd_Bewegung_Ende_am as date) between t1.von and t1.bis  
							join ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer t3		 on	 t2.FallID=t3.FallID  and t2.Datensatz_gueltig_von between t3.Datensatz_gueltig_von and t3.Datensatz_gueltig_bis
					where Fall_PEPP=1
					)
				Select FallID, ZeitraumID, RowID_Bewegungen_Verweildauer
						,Min(Bewegung_Beginn) as Bewegung_Beginn
						,Max(Bewegung_Ende) as Bewegung_Ende
						,Sum(Belegungstage_letzter_Tag)																					as Belegungstage_letzter_Tag 
						,Max(Fall_Tage_ohne_Berechnung_MD)																				as Fall_Tage_ohne_Berechnung_MD
						,Sum(datediff(d,Bewegung_Beginn,Bewegung_Ende))																	as Behandlungstage
						,Sum(datediff(d,Bewegung_Beginn,Bewegung_Ende)+ Belegungstage_letzter_Tag)										as Belegungstage
						,Sum(datediff(d,Bewegung_Beginn,Bewegung_Ende)+ Belegungstage_letzter_Tag) - Max(Fall_Tage_ohne_Berechnung_MD)	as Verweildauer 
						,Min(Fall_Aufnahme_am) as Aufnahme_am
						,Max(Verweildauer) as Verweildauer_Gesamt
						,Kalkulationsmonat,Kalkulationsmonat_von,Kalkulationsmonat_bis
						,Datensatz_gueltig_von, Datensatz_gueltig_bis
				into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat_Temp1
				from Aufteilung 
				group by FallID, ZeitraumID, RowID_Bewegungen_Verweildauer,Kalkulationsmonat,Kalkulationsmonat_von,Kalkulationsmonat_bis,Datensatz_gueltig_von, Datensatz_gueltig_bis
				order by FallID,ZeitraumID
				')
				--Select * from Bewegungen_Verweildauer_PEPP_Monat_Temp1 where FallID in ('10000010016811174x','10000010017523841x','10000010018028158x','10000010017583017x','10000010014891412x','10000010018316883' ) 
				--Select * from Bewegungen_AufnahmeEntlassung3 where FallID in ('10000010016811174x','10000010017523841x','10000010018028158x','10000010017583017x','10000010014891412' ) and ZeitraumID=2
				--Select * from Bewegungen_Verweildauer where FallID in ('10000010016811174x','10000010017523841x','10000010018028158x','10000010017583017x','10000010014891412' ) and ZeitraumID=2

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post210:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post210'
			SET @StepText= Concat('','Erstellen der Tabelle [Bewegungen_Verweildauer_PEPP_Monat_Temp2]')

			Set @SQL = Concat('
			Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat_Temp2;

			select *
				,cast(HASHBYTES(''SHA1'', (select Bewegung_Beginn, Bewegung_Ende, Belegungstage, Fall_Tage_ohne_Berechnung_MD, Verweildauer, Aufnahme_am FOR XML RAW))  as varbinary(100)) as HashID
			into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat_Temp2
			from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat_Temp1 
			')
			--Select * from Bewegungen_Verweildauer_PEPP_Monat_Temp2 where FallID in ('10000010016811174x','10000010017523841x','10000010018028158x','10000010018770414' ) and Kalkulationsmonat='2016-2' order by ZeitraumID

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post220:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post220'
			SET @StepText= Concat('','Erstellen der Tabelle [Bewegungen_Verweildauer_PEPP_Monat_Temp3]')

			Set @SQL = Concat('
			Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat_Temp3;
			Select distinct 
						 t1.FallID, t1.RowID_Bewegungen_Verweildauer, t1.Kalkulationsmonat, t1.Kalkulationsmonat_von, t1.Kalkulationsmonat_bis 
						,t1.Bewegung_Beginn, t1.Bewegung_Ende, t1.Belegungstage_letzter_Tag, t1.Fall_Tage_ohne_Berechnung_MD, t1.Belegungstage, t1.Verweildauer, t1.Aufnahme_am, t1.Verweildauer_Gesamt, t1.HashID
						,case when t1.HashID=LAG(t1.HashID) over (partition by t1.FallID, t1.Kalkulationsmonat, t1.HashID order by t1.Datensatz_gueltig_von) 
							and t1.Datensatz_gueltig_von = DateAdd(d,1,LAG(t1.Datensatz_gueltig_bis) over (partition by t1.FallID, t1.Kalkulationsmonat, t1.HashID  order by t1.Datensatz_gueltig_von))
							then 0 else 1 end ZeitSprung
						,t1.Datensatz_gueltig_von
						,t1.Datensatz_gueltig_bis
			into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat_Temp3
			from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat_Temp2 t1
			')
			--Select * from Bewegungen_Verweildauer_PEPP_Monat_Temp3 where Kalkulationsmonat='2024-7' and FallID in ('10000010016811174x','10000010017523841x','10000010018028158x','10000010018770414' ) 
			--Select * from Leistung_PEPP_Bezugsgroesse

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post230:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post230'
			SET @StepText= Concat('','Erstellen der Tabelle [Bewegungen_Verweildauer_PEPP_Monat_Temp4]')

			Set @SQL = Concat('
			Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat_Temp4;
			Select *
				,Sum(ZeitSprung) over (partition by FallID, Kalkulationsmonat, HashID order by Datensatz_gueltig_von ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)  as ZeitBlock
			into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat_Temp4
			from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat_Temp3
			')
			--Select * from Bewegungen_Verweildauer_PEPP_Monat_Temp4 where FallID in ('10000010016811174x','10000010017523841x','10000010018028158x','10000010018770414' ) 

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post240:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post240'
			SET @StepText= Concat('','Erstellen der Tabelle [Bewegungen_Verweildauer_PEPP_Monat]')

			Set @SQL = Concat('
			Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat;
			Select IDENTITY(BIGINT,1,1) AS RowID 
				,t1.FallID, t2.SchluesselID, t1.Kalkulationsmonat, t1.Kalkulationsmonat_von, t1.Kalkulationsmonat_bis, t1.RowID_Bewegungen_Verweildauer
				,t1.Belegungstage, t1.Fall_Tage_ohne_Berechnung_MD, t1.Verweildauer, t1.Verweildauer_Gesamt, t1.Aufnahme_am, t3.Bezugsgroesse, t1.HashID
				,Dense_Rank() over (partition by t1.FallID, t1.Kalkulationsmonat order by Min(t1.Datensatz_gueltig_von) DESC) as Rang
				,1 as LastChangeOnDate
				,Min(t1.Datensatz_gueltig_von) as Datensatz_gueltig_von
				,Max(t1.Datensatz_gueltig_bis) as Datensatz_gueltig_bis
			into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat 
			from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat_Temp4 t1
				join (Select Distinct FallID, Kalkulationsmonat, Row_Number() over (order by FallID, Kalkulationsmonat) as SchluesselID 
					  from (
							Select Distinct FallID, Kalkulationsmonat from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat_Temp4
							) t
					) t2 on t1.FallID=t2.FallID and t1.Kalkulationsmonat=t2.Kalkulationsmonat
				left join ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Leistung_PEPP_Bezugsgroesse t3 on cast(t1.Aufnahme_am as date) between t3.Datensatz_gueltig_von and t3.Datensatz_gueltig_bis
			group by t1.FallID, t2.SchluesselID, t1.Kalkulationsmonat, t1.Kalkulationsmonat_von, t1.Kalkulationsmonat_bis, t1.RowID_Bewegungen_Verweildauer
				,t1.Belegungstage, t1.Fall_Tage_ohne_Berechnung_MD, t1.Verweildauer, t1.Verweildauer_Gesamt, t1.Aufnahme_am, t1.HashID, t3.Bezugsgroesse

			CREATE UNIQUE NONCLUSTERED INDEX xFallID ON ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat	(FallID ASC, Kalkulationsmonat ASC, Datensatz_gueltig_von ASC) ;
				
			ALTER TABLE ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat
			ADD CONSTRAINT PK_Bewegungen_Verweildauer_PEPP_Monat_RowID PRIMARY KEY CLUSTERED (RowID);	
			')
			--Select * from Bewegungen_Verweildauer_PEPP_Monat where FallID in ('10000010016811174x','10000010017523841x','10000010018028158x','10000010017583017x','10000010018655249' ) and ZeitBlock=1 Kalkulationsmonat='2020-10'

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post250:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post250'
			SET @StepText= Concat('','Update der Tabelle [Admin_TabTree]')

			Set @SQL = Concat('
			Delete ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_TabTree where TargetTableDB=''',@SQL_TableTargetDB,''' and TargetTableSchema=''',@SQL_TableTargetSchema,''' and TargetTableName=''Bewegungen_Verweildauer_PEPP_Monat'';

			Insert into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_TabTree
			Values ((SELECT isnull(MAX(RelationID),1) + 1 FROM ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_TabTree),
			''',@SQL_TableTargetDB,''',
			''',@SQL_TableTargetSchema,''',
			''Bewegungen_Verweildauer_PEPP_Monat'',
			(Select Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat'',''U'')) ,
			''SchluesselID'',
			''RowID_Verweildauer_PEPP_Monat'',
			Getdate(),
			(SELECT max(p.rows) as Zeilen
					FROM sys.tables AS tbl
					JOIN sys.indexes as i ON i.object_id = tbl.object_id
					JOIN sys.partitions as p ON p.object_id = i.object_id and p.index_id = i.index_id
					JOIN sys.allocation_units as a ON a.container_id = p.partition_id
					where tbl.object_id=Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat'',''U'')),
			(SELECT ISNULL(8 * SUM(CASE WHEN a.type <> 1 THEN a.used_pages WHEN p.index_id < 2 THEN a.data_pages ELSE 0 END),0.0) as Speicherplatz
					FROM sys.tables AS tbl
					JOIN sys.indexes as i ON i.object_id = tbl.object_id
					JOIN sys.partitions as p ON p.object_id = i.object_id and p.index_id = i.index_id
					JOIN sys.allocation_units as a ON a.container_id = p.partition_id
					where tbl.object_id=Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat'',''U'')),
			''',@SQL_TableTargetDB,''',
			''',@SQL_TableTargetSchema,''',
			''Bewegungen_Verweildauer'',
			(Select Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer'',''U'')),
			(Select Distinct TargetID from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_TabTree where TargetObjectID=Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer'',''U'')),
			''RowID'',
			(Select modify_date from ',@SQL_TableTargetDB,'.sys.tables where object_id=Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer'',''U'')),
			Null,
			Null,
			1,
			''valid'',
			''F'',
			0,
			''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_Log'')
			')

			/*
			Select * from Bewegungen_Verweildauer_PEPP_Monat where FallID='10000010018316883' order by FallID, Kalkulationsmonat,Rang
			Select * from Bewegungen_Verweildauer where FallID='10000010015921554'

			Select FallID from Bewegungen_Verweildauer_PEPP_Monat
			group by FallID , Kalkulationsmonat , Datensatz_gueltig_von
			having count(*)>1
			*/

			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post260:
			if @TEMPLoeschen<>0
				Begin
					SET @SQL=''; SET @SQL1=''; SET @SQL2=''
					SET @StepPraefix='Post260'
					SET @StepText= Concat('','Löschen aller Temp-Tabellen')

					Set @SQL = Concat('
					Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung1;
					Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung2;
					--Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung3;
					Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung4;
					Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung5;
					Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_AufnahmeEntlassung6;
					Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat_Temp1;
					Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat_Temp2;
					Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat_Temp3;
					Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Bewegungen_Verweildauer_PEPP_Monat_Temp4;
					')

					EXEC(@SQL+@SQL1+@SQL2);
					SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
					EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

					if @Fehler>0
						goto Fehlermarke
				End
		end

	Execute dbo.Logging @LogID=@LogID,
						@LogTableProcessStatus='FINISHED',
						@LogTableProcessMode=@Ladeverfahren,
						@LogStep='END',
						@LogStepSQL='',
						@LogStepRows=0,
						@LogStepStatus='FINISHED'

Fehlermarke:
Endmarke:

end;








