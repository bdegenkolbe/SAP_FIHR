USE Analysen
GO

--exec dbo.UpdateBaseTable_Diagnosen_Aenderungshistorie @Ladeverfahren = 'FN', @PreProcessing=1, @MainProcessing=1, @PostProcessing=1, @TEMPPraefix=102194899, @CDPOS_laden=2, @TEMPLoeschen=1
--exec dbo.UpdateBaseTable_Diagnosen_Aenderungshistorie @Ladeverfahren = 'F', @PreProcessing=0, @MainProcessing=1, @PostProcessing=0, @TEMPPraefix=102194899, @CDPOS_laden=0, @TEMPLoeschen=0, @TestLoop='Top 100', @SQL_TableSource_Where='cast(|x|FALNR as bigint) in (16963236,18436162,16554730,16556964,15248938)'

CREATE or ALTER PROC dbo.UpdateBaseTable_Diagnosen_Aenderungshistorie

	@DELAY int						=10,	--> Greift im Fasttrack auch die Daten n-Tage vor dem letzten Ladevorgang ab. 
	@MaxDelay	as bigint			=0,		--> Maximale Verzögerung des letzten Aktualisierung einer Quelltabelle in Minuten. Insofern 0 oder negative Zahlen verwendet werden, bezieht sich die Verzögerung auf Tage. (0 die Aktualisierung muss von heute sein, -1 die Aktualisierung muss von gestern sein)
	@DaysToFullLoad int				=7,		--> Aller wieviel Tage soll ein Fullload durchgeführt werden?
	@TestLoop nvarchar(100)			='',	--> bspw. 'Top 100' für 100 Testdatensätze
	@DeltaDays as int				=1,		--> Delta-Load beinhaltet n volle Tage 
	@FullloadYears as int			=5,		--> Jahre die als Fullload geladen werden sollen, 0=Delta-Load
	@Ladeverfahren as nvarchar(2)	='',	--> Wenn 'F' dann Fulload für alle geänderten Tabellen, wenn 'D' dann Deltaload, wenn 'FN' Fulload für alle Tabellen. Sonst entscheidet das Skript automatische über das Ladeverfahren anhand der Einstellungen
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

	@SQL_TableSource_Where as nvarchar(max) = '', --> Filter der Originaltabelle ohne Where-Befehl --> 'cast(|x|FALNR as bigint) in (17942266)'
	@SQL_TableTargetDB as nvarchar(200)		= 'Analysen',	--> Übergabeparameter für DIAS
	@SQL_TableTargetSchema as nvarchar(200)	= 'dbo',		--> Übergabeparameter für DIAS
	@SQL_TableSourceDB as nvarchar(200)		=  'replicate',
	@SQL_TableSourceSchema as nvarchar(200)	= 'sap'
as
Begin
	
	PRINT 'Starte Skripabarbeitung'
	
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

	Execute dbo.Logging @LogID=@LogID Output, 
						@LogTableName='Diagnosen',
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

			Print 'PreProcessing'

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
			SET @StepPraefix='Pre20'
			SET @StepText= Concat('','UpdateBaseTable [Diagnosen_Katalog]')
			--NKDI: Diagnosen_Katalog
			--Select * from replicate.sap.NKDI
			--Declare @TEMPPraefix as nvarchar(100); Declare @TEMPLoeschen as int; Declare @SQL_TableSourceDB as nvarchar(200);Declare @SQL_TableSourceSchema as nvarchar(200);Declare @SQL_TableTargetDB as nvarchar(200); Declare @SQL_TableTargetSchema as nvarchar(200); Declare @SQL as nvarchar(max); Declare @SQL1 as nvarchar(max); Declare @SQL2 as nvarchar(max); Set @SQL_TableTargetDB='Analysen'; Set @SQL_TableTargetSchema='dbo'; Set @TEMPLoeschen=1; Set @TEMPPraefix=62944979; Set @SQL_TableSourceSchema='sap'; SET @SQL_TableSourceDB='replicate'
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY =@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad =@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,
					@Ladeverfahren =@Ladeverfahren, @TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen,@Historisierung=0,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableSourceName='NKDI',
					@SQL_TableSourceFields='MANDT,DKAT,DKEY,REF_DKAT,REF_DKEY,DTEXT1,DTEXT2,DTEXT3,DTEXT4,GSCHL,ALTVON,ALTBIS,DTYP,ICD10GM_P301,ICD10GM_P295',
					@SQL_TableSourceID='concat(|x|MANDT,|x|DKAT,|x|DKEY)',
					@SQL_TableSourceCreateDate=	'cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceUpDate=		'cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceStornoDate=	'cast(''31.12.2099 23:59:59'' as datetime)',
					@SQL_TableSourceStornoFlag=	'0',	@ValidToStorno	= 1, @ValidBeforeStorno=0,
					@SQL_TableSource_Where='|x|SPRAS=''D''',
					@SQL_TableTargetName='Diagnosen_Code',
					@SQL_TableTargetID='|x|Diagnose_CodeID',
					@SQL_TableTargetDefinition1='
					DKEY as Diagnose_Code
					,concat(MANDT,DKAT) as Diagnosen_KatalogID
					,concat(DTEXT1,DTEXT2,DTEXT3,DTEXT4) as Diagnose_KurzText
					,case when len(GSCHL)>0 then GSCHL else Null end as Diagnose_Geschlecht
					,case when GSCHL=1 then ''männlich''
						  when GSCHL=2 then ''weiblich''
						  when GSCHL=3 then ''Sonstiges''
						  else Null end as Diagnose_Geschlecht_KurzText
					,Case when ALTVON>0 then cast(ALTVON as int) else 0 end Diagnose_Alter_von
					,Case when ALTBIS>0 then cast(ALTBIS as int) else 125 end Diagnose_Alter_bis
					,case when len(DTYP)>0 then DTYP else '''' end as Diagnose_Typ
					,ICD10GM_P301 as Diagnose_P301
					,ICD10GM_P295 as Diagnose_P295
					',
					@CDPOS_laden=0, @CDPOS_TableID	= '';

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PreProcessing', @LogStepError=@Fehler 

Pre30:
			SET @StepPraefix='Pre30'
			SET @StepText= Concat('','UpdateBaseTable [Diagnosen_KatalogText]')
			--TNK00: Diagnosen_KatalogText
			--Select * from replicate.sap.TNK00
			--Declare @TEMPPraefix as nvarchar(100); Declare @TEMPLoeschen as int; Declare @SQL_TableSourceDB as nvarchar(200);Declare @SQL_TableSourceSchema as nvarchar(200);Declare @SQL_TableTargetDB as nvarchar(200); Declare @SQL_TableTargetSchema as nvarchar(200); Declare @SQL as nvarchar(max); Declare @SQL1 as nvarchar(max); Declare @SQL2 as nvarchar(max); Set @SQL_TableTargetDB='Analysen'; Set @SQL_TableTargetSchema='dbo'; Set @TEMPLoeschen=1; Set @TEMPPraefix=62944979; Set @SQL_TableSourceSchema='sap'; SET @SQL_TableSourceDB='replicate'
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY =@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad =@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,
					@Ladeverfahren =@Ladeverfahren, @TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen,@Historisierung=0,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableSourceName='TNK00',
					@SQL_TableSourceFields='MANDT,KATID,KATKB,KATTX',
					@SQL_TableSourceID='concat(|x|MANDT,|x|KATID)',
					@SQL_TableSourceCreateDate=	'cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceUpDate=		'cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceStornoDate=	'cast(''31.12.2099 23:59:59'' as datetime)',
					@SQL_TableSourceStornoFlag=	'0',	@ValidToStorno	= 1, @ValidBeforeStorno=0,
					@SQL_TableSource_Where='',
					@SQL_TableTargetName='Diagnosen_Katalog',
					@SQL_TableTargetID='|x|Diagnose_KatalogID',
					@SQL_TableTargetDefinition1='
					KATKB as Katalog_Typ
					,KATTX as Katalog_KurzText
					',
					@CDPOS_laden=0, @CDPOS_TableID	= '';

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PreProcessing', @LogStepError=@Fehler 

		End

	if @MainProcessing=1
		Begin
			
			Print 'MainProcessing'

			SET @StepPraefix='Main10'
			SET @StepText= Concat('','UpdateBaseTable_Aenderungshistorie [Diagnosen_Aenderungshistorie]')	

			--Declare @TEMPPraefix as nvarchar(100); Declare @MaxDelay as int; Declare @Delay as int; Declare @TEMPLoeschen as int; Declare @SQL_TableSource_Where as nvarchar(500); Declare @SQL_TableSourceDB as nvarchar(200); Declare @SQL_TableSourceSchema as nvarchar(200); Declare @SQL_TableTargetDB as nvarchar(200); Declare @SQL_TableTargetSchema as nvarchar(200); Declare @SQL_TableSource_Join as nvarchar(max); Declare @SQL1 as nvarchar(max); Declare @SQL2 as nvarchar(max); Set @SQL_TableTargetDB='Analysen'; Set @SQL_TableTargetSchema='dbo'; Set @TEMPLoeschen=0; Set @TEMPPraefix=62944979; SET @MaxDelay=-1; SET @SQL_TableSourceDB='replicate'; SET @SQL_TableSourceSchema='sap'
			SET @SQL_TableSource_Join=Concat(' join ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Filter_Fallnummer tFilter on cast(|x|FALNR as bigint)=tFilter.FALNR')
			--SET @SQL_TableSource_Where='|x|FALNR in (18597541,18608502,18610193,18631718,18654177,18657938,18659681,18664692,18671778,18696419,18712488)'

			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY =@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad =@DaysToFullLoad,@TestLoop=@TestLoop,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,
					@Ladeverfahren =@Ladeverfahren,@CDPOS_laden=@CDPOS_laden,@LastChangeFromTarget=@LastChangeFromTarget,
					@HashAbgleich_ct =@HashAbgleich_ct,@Historisierung=@Historisierung,
					@StartStep=@StartStep,@LastChangeOnDate=@LastChangeOnDate,@ValidToStorno=@ValidToStorno,@ValidBeforeStorno=@ValidBeforeStorno,
					@SQL_TableSource_Where=@SQL_TableSource_Where,
					@SQL_TableSource_Join = @SQL_TableSource_Join,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@TEMPPraefix=@TEMPPraefix,@TEMPLoeschen=@TEMPLoeschen,
					@SQL_TableSourceName='NDIA',
					@SQL_TableSourceFields='MANDT,EINRI,FALNR,PATNR,LFDBEW,LFDNR,DKAT1,DKEY1,DKAT2,DKEY2,DIAGW,DTYP1,DIALO,EWDIA,BHDIA,AFDIA,ENDIA,FHDIA,KHDIA,OPDIA,DIAPR,ARDIA,PODIA,TUDIA,KZTXT,DRG_DIA_SEQNO,DRG_CATEGORY,DRG_RELVANT,CCL,DIADT,DIAZT',
					@SQL_TableSourceID='concat(|x|MANDT,|x|EINRI,|x|FALNR,|x|LFDNR)',
					@SQL_TableSourceCreateDate=	'try_cast(|x|ERDAT as datetime) + cast(|x|ERTIM as datetime)',
					@SQL_TableSourceStornoDate=	'case when len(|x|STUSR)>0 and try_cast(|x|STDAT as datetime) >0 then cast(|x|STDAT as datetime) + cast(''23:59:59'' as datetime) else cast(''31.12.2099 23:59:59'' as datetime) end',
					@SQL_TableSourceStornoFlag=	 'case when len(|x|STUSR)>0 then 1 else 0 end',
					@SQL_TableSourceStornoField = '|x|STUSR' ,
					@SQL_TableSourceUpDate='case when year(|x|UPDAT) between 1990 and 2099 and try_cast(|x|UPDAT as datetime) is not null then cast(|x|UPDAT as datetime) + cast(''00:00:00'' as datetime) else try_cast(|x|ERDAT as datetime) + cast(|x|ERTIM as datetime) end ',
					@CDPOS_TableID	= 'concat(|x|MANDANT,|x|OBJECTID,right(|x|TABKEY,3))', 
					@SQL_TableTargetName='Diagnosen_Aenderungshistorie',
					@SQL_TableTargetID='|x|DiagnoseID', 
					@SQL_TableTargetDefinition1=	'
					concat(MANDT,EINRI,FALNR) as FallID
					,concat(MANDT,EINRI,FALNR,LFDBEW) as BewegungID

					,cast(FALNR as bigint) as Fallnummer
					,cast(LFDBEW as int) as Bewegung_Nummer
					,cast(LFDNR as int) as Diagnose_Nummer

					,DKEY1 as Diagnose_Code
					,DKEY2 as Diagnose_Code2
					,concat(MANDT,DKAT1,DKEY1) as Diagnose_CodeID
					,concat(MANDT,DKAT2,DKEY2) as Diagnose_CodeID2
					,concat(MANDT,DKAT1) as Diagnose_KatalogID
					,concat(MANDT,DKAT2) as Diagnose_KatalogID2

					,case when len(trim(DIAGW))>0 then DIAGW	 else Null end as Diagnose_Sicherheit
					,case when len(trim(DTYP1))>0 then DTYP1	 else Null end as Diagnose_Zusatz
					,case when len(trim(DIALO))>0 then DIALO	 else Null end as Diagnose_Lokalisation

					,case when EWDIA=''X'' then 1 else 0 end  as Diagnose_ist_Einweisungsdiagnose
					,case when BHDIA=''X'' then 1 else 0 end  as Diagnose_ist_Behandlungsdiagnose
					,case when AFDIA=''X'' then 1 else 0 end  as Diagnose_ist_Aufnahmediagnose
					,case when ENDIA=''X'' then 1 else 0 end  as Diagnose_ist_Entlassungsdiagnose
					,case when FHDIA=''X'' then 1 else 0 end  as Diagnose_ist_Fachabteilungshaupt
					,case when KHDIA=''X'' then 1 else 0 end  as Diagnose_ist_Hauptdiagnose
					,case when OPDIA=''X'' then 1 else 0 end  as Diagnose_ist_Operationsdiagnose
					,case when DIAPR=''X'' then 1 else 0 end  as Diagnose_ist_med_Nebendiagnose
					,case when ARDIA=''X'' then 1 else 0 end  as Diagnose_ist_Arbeitsdiagnose
					,case when PODIA=''X'' then 1 else 0 end  as Diagnose_ist_Praeoperativ
					,case when TUDIA=''X'' then 1 else 0 end  as Diagnose_ist_Todesursache

					,KZTXT as Diagnose_Bemerkung

					,case when KHDIA=''X'' then ''HD'' else ''ND'' end as Diagnose_Art

					,try_cast(DRG_DIA_SEQNO as int) as Diagnose_DRG_SeqNummer
					,case DRG_CATEGORY 
								when ''S'' then ''Nebendiagnose (S)''
								when ''P'' then ''Hauptdiagnose (P)''
								else ''keine DRG-Diagnose'' end as Diagnose_DRG_Kategorie_KurzText
					,DRG_CATEGORY as Diagnose_DRG_Kategorie
					,case when DRG_RELVANT=''X'' then 1 else 0 end Diagnose_DRG_Relevant
					,try_cast(CCL as int) as Diagnose_DRG_CCL

					,try_cast(DIADT as datetime) + try_cast(DIAZT as datetime) as Diagnose_gestellt_am
					';

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='MainProcessing', @LogStepError=@Fehler 

		end

	if @PostProcessing=1
		Begin
			print 'PostProcessing'
Post10:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post10'
			SET @StepText= Concat('','TabJoin [Diagnosen_Basiscube]')	
			--Select * from Diagnosen_Basiscube_Test 
			--Select * from Bewegungen_BasisCube where BewegungID='1000001001859754100017'
			--Declare @TEMPPraefix as nvarchar(100); Declare @TEMPLoeschen as int; Declare @SQL_TableTargetDB as nvarchar(200); Declare @SQL_TableTargetSchema as nvarchar(200); Declare @SQL as nvarchar(max); Declare @MaxDelay as int; Declare @SQL1 as nvarchar(max); Declare @SQL2 as nvarchar(max); Set @SQL_TableTargetDB='Analysen'; Set @SQL_TableTargetSchema='dbo'; Set @TEMPLoeschen=0; Set @TEMPPraefix=62944979; Set @MaxDelay=0
			Execute [dbo].[TabJoin] 
					@SQL_Table1_SourceDB	=@SQL_TableTargetDB, @SQL_Table1_SourceSchema =@SQL_TableTargetSchema,@TEMPPraefix=@TEMPPraefix, @TEMPLoeschen=@TEMPLoeschen, @MaxDelay=@MaxDelay,
					@SQL_Table1_SourceName	='Diagnosen_Aenderungshistorie',	@SQL_Table1_ID ='|x|DiagnoseID',					@SQL_TableTargetRowID1 ='|x|RowID_Diagnose',		@SQL_Table1_SourceFields='|x|BewegungID as Diagnose_BewegungID_Alt',
					@SQL_Table2_SourceName	='Fallzusammenfuehrung_Diagnosen',	@SQL_Table1_Connect_ID2 ='|x|DiagnoseID',			@SQL_Table2_Connect_ID ='|x|DiagnoseID_Alt',		@SQL_TableTargetRowID2 ='|x|RowID_Fallzusammenfuehrung_Diagnose',	@SQL_Table2_SourceFields='|x|BewegungID as Diagnose_BewegungID_Neu', @SQL_Use_Table2_ID=1,
					@SQL_Table3_SourceName	='Bewegungen_BasisCube',			@SQL_Table1_Connect_ID3 ='|x|BewegungID',			@SQL_Table3_Connect_ID ='|x|BewegungID_Alt',		@SQL_TableTargetRowID3 ='|x|RowID_Bewegung',						--@SQL_Table3_SourceWhere ='isnull(|xBase|Diagnose_BewegungID_Neu,|xBase|Diagnose_BewegungID_Alt)=|x|BewegungID',
					@SQL_Table4_SourceName	='Diagnosen_Code',					@SQL_Table1_Connect_ID4 ='|x|Diagnose_CodeID',		@SQL_Table4_Connect_ID ='|x|Diagnose_CodeID',		@SQL_TableTargetRowID4 ='|x|RowID_Katalog', 
					@SQL_Table5_SourceName	='Diagnosen_Katalog',				@SQL_Table1_Connect_ID5 ='|x|Diagnose_KatalogID',	@SQL_Table5_Connect_ID ='|x|Diagnose_KatalogID',	@SQL_TableTargetRowID5 ='|x|RowID_KatalogText', 
					@SQL_TableTargetName	='Diagnosen_Basiscube',				@SQL_TableTargetID='|x|DiagnoseID',
					@SQL_TableTargetDefinition1='
				isnull(t2.DiagnoseID,t1.DiagnoseID) as DiagnoseID
				,t2.AbrechnungID	
				,isnull(t2.DiagnoseID_Alt,t1.DiagnoseID)		as DiagnoseID_Alt
				,isnull(t2.FallID,t1.FallID)					as FallID
				,isnull(t2.FallID_Alt,t1.FallID)				as FallID_Alt
				,isnull(t2.BewegungID,t1.BewegungID)			as BewegungID
				,isnull(t2.BewegungID_Alt,t1.BewegungID)		as BewegungID_Alt
				,isnull(t2.Diagnose_Nummer,t1.Diagnose_Nummer)	as Diagnose_Nummer
				,isnull(t2.Diagnose_Nummer_Alt,t1.Diagnose_Nummer)		as Diagnose_Nummer_Alt

				,t1.Diagnose_Code
				,t4.Diagnose_KurzText
				,t5.Katalog_KurzText as Diagnose_Katalog_KurzText
				,t1.Diagnose_Sicherheit
				,t1.Diagnose_Zusatz
				,t1.Diagnose_Lokalisation
				,t1.Diagnose_ist_Einweisungsdiagnose
				,t1.Diagnose_ist_Behandlungsdiagnose
				,t1.Diagnose_ist_Aufnahmediagnose
				,t1.Diagnose_ist_Entlassungsdiagnose
				,t1.Diagnose_ist_Fachabteilungshaupt
				,t1.Diagnose_ist_Hauptdiagnose
				,t1.Diagnose_ist_Operationsdiagnose
				,t1.Diagnose_ist_med_Nebendiagnose
				,t1.Diagnose_ist_Arbeitsdiagnose
				,t1.Diagnose_ist_Praeoperativ
				,t1.Diagnose_ist_Todesursache
				,t1.Diagnose_Bemerkung
				,t1.Diagnose_Art

				,isnull(t2.Diagnose_DRG_SeqNummer,t1.Diagnose_DRG_SeqNummer) as Diagnose_DRG_SeqNummer
				,isnull(t2.Diagnose_DRG_Kategorie,t1.Diagnose_DRG_Kategorie) as Diagnose_DRG_Kategorie
				,isnull(t2.Diagnose_DRG_Kategorie_KurzText,t1.Diagnose_DRG_Kategorie_KurzText) as Diagnose_DRG_Kategorie_KurzText
				,isnull(t2.Diagnose_DRG_Relevant,t1.Diagnose_DRG_Relevant) as Diagnose_DRG_Relevant
				,isnull(t2.Diagnose_DRG_CCL,t1.Diagnose_DRG_CCL) as Diagnose_DRG_CCL

				,isnull(t2.Diagnose_ist_storniert,0) as Diagnose_ist_storniert
				';
				
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 
				
		End

		Execute dbo.Logging @LogID=@LogID,
						@LogTableProcessStatus='FINISHED',
						@LogTableProcessMode=@Ladeverfahren,
						@LogStep='END',
						@LogStepSQL='',
						@LogStepRows=0,
						@LogStepStatus='FINISHED'
end;

goto Endmarke

Fehlermarke:
		Print 'FEHLER!!!!!!!!!!!!!!!!!!!!!!!'
		Print @@Error

		Set @SQL= concat('
						Zyklus				:',@DaysToFullLoad,'
						TestDurchLauf		:',@TestLoop,'
						Delta				:',@DeltaDays,'
						Fullload			:',@FullloadYears,'
						Ladeverfahren		:',@Ladeverfahren,'
						TEMPPraefix			:',@TEMPPraefix,'
					')

		Execute dbo.Logging @LogID=@LogID,
							@LogTableProcessStatus='ERROR',
							@LogStep='END',
							@LogStepSQL=@SQL,
							@LogStepRows=@Zeilenanzahl,
							@LogStepStatus='ERROR',
							@LogStepError=@Fehler
Endmarke:



/*
	SELECT  
			concat(t1.[MANDT],t1.[EINRI],t1.[FALNR]) as Fall_ID
			,t1.[FALNR] as Fallnummer
			,t1.LFDBEW as Bewegung_Nummer
			,t1.[LFDNR] as Diagnose_Nummer
			,t2.[KATTX] as Diagnose_Katalog
			,right(t2.KATTX,4) as Diagnose_Jahr
			,t1.[DKEY1] as Diagnose_Code
			,t3.[Klasse_Text] as Diagnose_Text
			,t3.Kapitel_Nummer + ' - ' + t3.Kapitel_Text as Diagnose_Kapital
			,t3.Gruppe_Text
			,t3.ICD3_Kategorie + ' - ' + ICD3_Kategorie_Text as Diagnose_Kategorie
			,case when len(t3.ICD4_Text)>0 then t3.ICD4_Text + '('+ t3.ICD4 + ')'  else Null end as Diagnose_4Steller
			,case when len(t3.ICD5_Text)>0 then t3.ICD5_Text + '('+ t3.Kode + ')' else Null end as Diagnose_5Steller
         
		    ,case when len(trim(t1.[DIAGW]))>0 then t1.[DIAGW]	 else Null end as Diagnose_Sicherheit
			,case when len(trim(t1.[DTYP1]))>0 then t1.[DTYP1]	 else Null end as Diagnose_Zusatz
			,case when len(trim(t1.[DIALO]))>0 then t1.[DIALO]	 else Null end as Diagnose_Lokalisation

			,case when t1.[EWDIA]='X' then 1 else 0 end  as Diagnose_ist_Einweisungsdiagnose
			,case when t1.[BHDIA]='X' then 1 else 0 end  as Diagnose_ist_Behandlungsdiagnose
			,case when t1.[AFDIA]='X' then 1 else 0 end  as Diagnose_ist_Aufnahmediagnose
			,case when t1.[ENDIA]='X' then 1 else 0 end  as Diagnose_ist_Entlassungsdiagnose
			,case when t1.[FHDIA]='X' then 1 else 0 end  as Diagnose_ist_Fachabteilungshaupt
			,case when t1.[KHDIA]='X' then 1 else 0 end  as Diagnose_ist_Hauptdiagnose
			,case when t1.[OPDIA]='X' then 1 else 0 end  as Diagnose_ist_Operationsdiagnose
			,case when t1.[DIAPR]='X' then 1 else 0 end  as Diagnose_ist_med_Nebendiagnose
			,case when t1.[ARDIA]='X' then 1 else 0 end  as Diagnose_ist_Arbeitsdiagnose
			,case when t1.[PODIA]='X' then 1 else 0 end  as Diagnose_ist_Praeoperativ
			,case when t1.[TUDIA]='X' then 1 else 0 end  as Diagnose_ist_Todesursache

			,t1.[KZTXT] as Diagnose_KZ_Bemerkung

			,case when t1.[KHDIA]='X' then 'HD' else 'ND' end as Diagnose_Art

			,case t1.[DRG_CATEGORY] 
						when 'S' then 'Nebendiagnose (S)'
						when 'P' then 'Hauptdiagnose (P)'
						else 'keine DRG-Diagnose' end as Diagnose_DRG_Kategorie
			,case when t1.[DRG_RELVANT]='X' then 1 else 0 end Diagnose_DRG_Relevant
			,try_cast(t1.[CCL] as int) as Diagnose_DRG_CCL

			,try_cast(t1.[DIADT] as datetime) + try_cast(t1.[DIAZT] as datetime) as Diagnose_gestellt_am
	  		,try_cast(t1.ERDAT as date) as Diagnose_gueltig_von
			,case when t1.STORN='X' then try_cast(t1.STDAT as date) else cast('31.12.2099' as date) end Diagnose_gueltig_bis

			,getdate() as Tab_erstellt_am

	  into [Replicate].test.Diagnosen_temp
	  FROM [Replicate].[sap].[NDIA] t1
		   left join [Replicate].[sap].[TNK00] t2 on t2.KATID=t1.DKAT1

		    select * from [Replicate].[sap].NKDI
			select * from [Replicate].[sap].[TNK00] 
			select * from [Replicate].[sap].[NDIA] t1
			left join [Replicate].[sap].[TNK00] t2 on t2.KATID=t1.DKAT1
			left join [Replicate].[sap].NKDI t3 on t3.DKEY=t1.DKEY1

			TN26E
			TN26C
			*/