USE Analysen
GO

--exec dbo.UpdateBaseTable_Falldaten_Aenderungshistorie @Ladeverfahren = 'FN', @PreProcessing=1, @MainProcessing=1, @PostProcessing=1, @TEMPPraefix=102194899, @CDPOS_laden=0, @TEMPLoeschen=1
--exec dbo.UpdateBaseTable_Falldaten_Aenderungshistorie @Ladeverfahren = 'F', @PreProcessing=0, @MainProcessing=0, @PostProcessing=1, @TEMPPraefix=102194890, @CDPOS_laden=0, @TEMPLoeschen=0, @SQL_TableSource_Where='cast(|x|FALNR as bigint) in (16963236,18436162,16554730,16556964,15248938)'
--Select * from Falldaten_Aenderungshistorie_Test where Fallnummer=18347223 order by datensatz_gueltig_von

CREATE or ALTER PROC dbo.UpdateBaseTable_Falldaten_Aenderungshistorie

	@DELAY int						=10,	--> Greift im Fasttrack auch die Daten n-Tage vor dem letzten Ladevorgang ab. 
	@MaxDelay	as int				=0,		--> Maximale Verzögerung des letzten Aktualisierung einer Quelltabelle in Minuten. Insofern 0 oder negative Zahlen verwendet werden, bezieht sich die Verzögerung auf Tage. (0 die Aktualisierung muss von heute sein, -1 die Aktualisierung muss von gestern sein)
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
	@SQL_TableTargetName as nvarchar(200)	= 'Falldaten_Aenderungshistorie'	--> Übergabeparameter für DIAS

as
Begin

	PRINT 'Starte Skripabarbeitung'
	Print @MaxDelay
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
	DECLARE @SQL_TableTargetDefinition1 as nvarchar(max)
	DECLARE @SQL_TableTargetDefinition2 as nvarchar(max)
	DECLARE @SQL_TableTargetUpDate as nvarchar(500)
	DECLARE @SQL_TableTargetCreateDate as nvarchar(500)
	DECLARE @SQL_TableTargetStornoDate as nvarchar(500)
	DECLARE @SQL_TableTargetStornoFlag as nvarchar(500)

	DECLARE @SQL_Variable1 as nvarchar(500)

	DECLARE @CDPOS_TableID as nvarchar(200)

	SET @SQL_TableSourceDB			= 'replicate'
	SET @SQL_TableSourceSchema		= 'sap'
	SET @SQL_TableSourceName		= 'NFAL'
	SET @SQL_TableSourceString		=  Concat(@SQL_TableSourceDB,'.',@SQL_TableSourceSchema,'.',@SQL_TableSourceName)
	SET @SQL_TableSourceID			= 'concat(|x|MANDT,|x|EINRI,|x|FALNR)'
	SET @SQL_TableSourceFields		= 'MANDT,EINRI,FALNR,PATNR,FOREI,TOB,MDTOB,KV_KZ,ABRKZ,EINZG,BEKAT,FALAR,FATYP,STATU,FSPER,STASP,MDVSTAT'
	SET @SQL_TableSourceUpDate		= 'case when try_cast(|x|UPDAT as datetime) >0 then cast(|x|UPDAT as datetime) + cast(''00:00:00'' as datetime) else try_cast(|x|ERDAT as datetime)+ cast(''00:00:00'' as datetime) end'
	SET @SQL_TableSourceCreateDate  = 'try_cast(|x|ERDAT as datetime) + cast(''00:00:00'' as datetime)'
	SET @SQL_TableSourceStornoDate  = 'case when |x|STORN=''X'' and try_cast(|x|STDAT as datetime) >0 then cast(|x|STDAT as datetime) + cast(''23:59:59'' as datetime) else cast(''31.12.2099 23:59:59'' as datetime) end'
	SET @SQL_TableSourceStornoFlag  = 'case when |x|STORN=''X'' then 1 else 0 end'
	SET @SQL_TableSourceStornoField = '|x|STORN'

	SET @SQL_TableTargetString		= Concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,'')
	SET @SQL_TableTargetID			= '|x|FallID'
	SET @CDPOS_TableID				= 'concat(|x|MANDANT,|x|OBJECTID)'

	SET @SQL_TableSource_Join		= Concat(' join ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Filter_Fallnummer tFilter on cast(|x|FALNR as bigint)=tFilter.FALNR')

	SET @SQL_TableTargetDefinition1=	'
						cast(|x|FALNR as bigint) as Fallnummer
						,CONCAT(|x|MANDT,|x|PATNR) as PatientenID

						,case when FOREI =''X'' then 1 else 0 end as Fall_ist_Auslandsfall 

						,cast(case when |x|MDTOB is null then 0 else |x|TOB end as int) as Fall_Tage_ohne_Berechnung_Pflege
						,cast(case when |x|MDTOB is null then |x|TOB else |x|MDTOB end as int) as Fall_Tage_ohne_Berechnung_MD
		
						,case when |x|KV_KZ=''X'' then 1 else 0 end as Fall_fuer_KV_Abrechnung_relevant
						,cast(|x|ABRKZ as int) as Fall_Abrechnung_Kennzeichen 
						,case try_cast(|x|ABRKZ  as int)
							when Null then ''Nicht abgerechnet''
							when 0 then ''Nicht abgerechnet''
							when 1 then ''Zwischenabgerechnet''
							when 2 then ''Endabgerechnet''
							when 3 then ''Vorläufige Rechnung''
							else ''Sonstiges'' end as Fall_Abrechnung_KurzText

						,cast(|x|EINZG as int) as Fall_Einzugsgebiet

						,cast(left(|x|BEKAT,5) as varchar(5)) as Fall_Behandlungskategorie
						,cast(left(tBEKAT.BLTXT,50) as varchar(50)) as Fall_Behandlungskategorie_KurzText
						
						,cast(|x|FALAR as int) as Fall_Art
						,case |x|FALAR 
							when 1 then ''Stationär'' 
							when 2 then ''Ambulant''
							when 3 then ''Teilstationär'' 
							else ''Unbekannt'' End as Fall_Art_KurzText

						,cast(left(|x|FATYP,5) as varchar(5)) as Fall_Typ
						,case |x|STATU 
							when ''I'' then ''Aktuell'' 
							when ''E'' then ''Abgeschlossen''
							when ''P'' then ''Plan'' 
							else ''Unbekannt'' End as Fall_Status

						,case when |x|FSPER=1 then 1 else 0 end as Fall_hat_Fakturasperre
						,case when |x|STASP=''X'' then 1 else 0 end as Fall_hat_Statistiksperre
						,case when |x|MDVSTAT=''X'' then 1 else 0 end as Fall_hat_Status_nach_MD_Verfahren

						--,try_cast(|x|RESPI as int) as Fall_hat_Beatmungsstunden'

	SET @SQL_TableTarget_Join=Concat('	left join ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.TN24T tBEKAT on |x|BEKAT = tBEKAT.BEKAT');

	if @PreProcessing=1
		Begin

			EXECUTE dbo.UpdateFilterTable_Fallnummer
			@Ladeverfahren=@Ladeverfahren, @TestLoop=@TestLoop, @FullloadYears=@FullloadYears,
			@SQL_TableSourceDB=@SQL_TableSourceDB, @SQL_TableSourceSchema=@SQL_TableSourceSchema, 
			@SQL_TableTargetDB=@SQL_TableTargetDB, @SQL_TableTargetSchema=@SQL_TableTargetSchema, @SQL_TableTargetName='Filter_Fallnummer'

			EXECUTE dbo.UpdateBaseTable_Fallzusammenfuehrung	@Ladeverfahren = @Ladeverfahren, @TEMPLoeschen = @TEMPLoeschen, @MaxDelay=@MaxDelay
			EXECUTE dbo.UpdateBaseTable_ISH_Organisation		@Ladeverfahren = @Ladeverfahren, @TEMPLoeschen = @TEMPLoeschen, @MaxDelay=@MaxDelay

			Set @SQL_PreProcessing1 = CONCAT('
			drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Falldaten_Merkmale

			Create table ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Falldaten_Merkmale
			(  
				FallID nvarchar(20),   
				Fall_Merkmal nvarchar(50)
			); 

			Insert into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Falldaten_Merkmale (FallID, Fall_Merkmal) 
			Values (''10000010018051927'',''Kinder2023'')
			,(''10000010017931873'',''Kinder2023'')
			,(''10000010018015622'',''Kinder2023'')
			,(''10000010018055633'',''Kinder2023'')
			,(''10000010018069052'',''Kinder2023'')
			,(''10000010018079709'',''Kinder2023'')
			,(''10000010018087604'',''Kinder2023'')
			,(''10000010018094357'',''Kinder2023'')
			,(''10000010018075934'',''Kinder2023'')
			,(''10000010018064668'',''Kinder2023'')
			,(''10000010018069018'',''Kinder2023'')
			,(''10000010018070706'',''Kinder2023'')
			,(''10000010018077913'',''Kinder2023'')
			,(''10000010018078136'',''Kinder2023'')
			,(''10000010018082845'',''Kinder2023'')
			,(''10000010018086301'',''Kinder2023'')
			,(''10000010018086723'',''Kinder2023'')
			,(''10000010018088206'',''Kinder2023'')
			,(''10000010018089213'',''Kinder2023'')
			,(''10000010018099115'',''Kinder2023'')
			,(''10000010018080106'',''Kinder2023'')
			,(''10000010018012684'',''Kinder2023'')
			,(''10000010018029290'',''Kinder2023'')
			,(''10000010018071496'',''Kinder2023'')
			,(''10000010018077760'',''Kinder2023'')
			,(''10000010018094834'',''Kinder2023'')
			,(''10000010018070390'',''Kinder2023'')
			,(''10000010018093525'',''Kinder2023'')
			,(''10000010018070356'',''Kinder2023'')
			,(''10000010018073121'',''Kinder2023'')
			,(''10000010018087802'',''Kinder2023'')');

			Set @SQL_PreProcessing2 = CONCAT('
			Insert into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Falldaten_Merkmale (FallID, Fall_Merkmal) 
			Values (''10000010018087443'',''Kinder2023'')
			,(''10000010018053859'',''Kinder2023'')
			,(''10000010018063489'',''Kinder2023'')
			,(''10000010018081879'',''Kinder2023'')
			,(''10000010018078200'',''Kinder2023'')
			,(''10000010018079735'',''Kinder2023'')
			,(''10000010018053467'',''Kinder2023'')
			,(''10000010018053860'',''Kinder2023'')
			,(''10000010018055938'',''Kinder2023'')
			,(''10000010018072419'',''Kinder2023'')
			,(''10000010018093534'',''Kinder2023'')
			,(''10000010018058111'',''Kinder2023'')
			,(''10000010018061923'',''Kinder2023'')
			,(''10000010018064705'',''Kinder2023'')
			,(''10000010018066764'',''Kinder2023'')
			,(''10000010018069053'',''Kinder2023'')
			,(''10000010018071306'',''Kinder2023'')
			,(''10000010018091682'',''Kinder2023'')
			,(''10000010018091683'',''Kinder2023'')
			,(''10000010018083881'',''Kinder2023'')
			,(''10000010018091511'',''Kinder2023'')
			,(''10000010018085946'',''Kinder2023'')
			,(''10000010018076532'',''Kinder2023'')
			,(''10000010018054439'',''Kinder2023'')
			,(''10000010018062041'',''Kinder2023'')
			,(''10000010018072436'',''Kinder2023'')
			,(''10000010018094182'',''Kinder2023'')
			,(''10000010018062249'',''Kinder2023'')
			,(''10000010018086191'',''Kinder2023'')
			,(''10000010018085854'',''Kinder2023'')
			,(''10000010018095910'',''Kinder2023'')
			,(''10000010018083886'',''Kinder2023'')
			,(''10000010018095062'',''Kinder2023'')
			,(''10000010018042446'',''Kinder2023'')
			,(''10000010018094651'',''Kinder2023'')
			,(''10000010018066862'',''Kinder2023'')
			,(''10000010018062688'',''Kinder2023'')
			,(''10000010018089973'',''Kinder2023'')
			,(''10000010018062701'',''Kinder2023'')
			,(''10000010018094835'',''Kinder2023'')
			,(''10000010018085182'',''Kinder2023'')
			,(''10000010018051948'',''Kinder2023'')
			,(''10000010018072406'',''Kinder2023'')
			,(''10000010018072388'',''Kinder2023'')
			,(''10000010018077693'',''Kinder2023'')
			,(''10000010018097343'',''Kinder2023'')
			,(''10000010018062000'',''Kinder2023'')
			,(''10000010018041416'',''Kinder2023'')
			,(''10000010018055796'',''Kinder2023'')
			,(''10000010018092474'',''Kinder2023'')
			,(''10000010018055067'',''Kinder2023'')
			,(''10000010018056028'',''Kinder2023'')
			,(''10000010018095271'',''Kinder2023'')
			,(''10000010018054109'',''Kinder2023'')
			,(''10000010018061153'',''Kinder2023'')
			,(''10000010018064589'',''Kinder2023'')
			,(''10000010018074963'',''Kinder2023'')
			,(''10000010018075955'',''Kinder2023'')
			,(''10000010018091413'',''Kinder2023'')
			,(''10000010018036436'',''Kinder2023'')
			,(''10000010018065252'',''Kinder2023'')
			,(''10000010018077761'',''Kinder2023'')');

			exec(@SQL_PreProcessing1)
			exec(@SQL_PreProcessing2)

		End

	if @MainProcessing=1
		Begin
			Execute dbo.UpdateBaseTable_Aenderungshistorie
				@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@TestLoop=@TestLoop,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@CDPOS_laden=@CDPOS_laden,@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
				@SQL_PreProcessing1=@SQL_PreProcessing1,@SQL_PreProcessing2=@SQL_PreProcessing2,@SQL_PreProcessing3=@SQL_PreProcessing3,@SQL_PreProcessing4=@SQL_PreProcessing4,@SQL_PreProcessing5=@SQL_PreProcessing5,
				@SQL_PostProcessing1=@SQL_PostProcessing1,@SQL_PostProcessing2=@SQL_PostProcessing2,@SQL_PostProcessing3=@SQL_PostProcessing3,@SQL_PostProcessing4=@SQL_PostProcessing4,@SQL_PostProcessing5=@SQL_PostProcessing5,
				@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,@SQL_TableSourceName=@SQL_TableSourceName,@SQL_TableSourceString=@SQL_TableSourceString,@SQL_TableSourceFields=@SQL_TableSourceFields,@SQL_TableSourceID=@SQL_TableSourceID,@SQL_TableSourceCreateDate=@SQL_TableSourceCreateDate,@SQL_TableSourceUpDate=@SQL_TableSourceUpDate,@SQL_TableSourceStornoDate=@SQL_TableSourceStornoDate,
				@SQL_TableSource_Join=@SQL_TableSource_Join,@SQL_TableSource_Kopf=@SQL_TableSource_Kopf,@SQL_TableSource_Fuss=@SQL_TableSource_Fuss,@SQL_TableSource_Where=@SQL_TableSource_Where,
				@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,@SQL_TableTargetName=@SQL_TableTargetName,@SQL_TableTargetString=@SQL_TableTargetString,@SQL_TableTargetFields=@SQL_TableTargetFields,@SQL_TableTargetID=@SQL_TableTargetID,@SQL_TableTarget_Join=@SQL_TableTarget_Join,@SQL_TableTargetDefinition1=@SQL_TableTargetDefinition1,@SQL_TableTargetDefinition2=@SQL_TableTargetDefinition2,@SQL_TableTargetUpDate=@SQL_TableTargetUpDate,@SQL_TableTargetCreateDate=@SQL_TableTargetCreateDate,@SQL_TableTargetStornoDate=@SQL_TableTargetStornoDate,
				@CDPOS_TableID=@CDPOS_TableID, @PreProcessing = @PreProcessing, @PostProcessing = @PostProcessing,	@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen,@SQL_TableSourceStornoFlag=@SQL_TableSourceStornoFlag, @SQL_TableTargetStornoFlag=@SQL_TableTargetStornoFlag, @SQL_TableSourceStornoField=@SQL_TableSourceStornoField,
				@ValidToStorno=@ValidToStorno, @ValidBeforeStorno=@ValidBeforeStorno, @StartStep = @StartStep,@LastChangeOnDate=@LastChangeOnDate
		end

	if @PostProcessing=1
		Begin

			EXECUTE dbo.UpdateBaseTable_Patienten_Aenderungshistorie
				@Ladeverfahren	= @Ladeverfahren
			,	@TestLoop		= @TestLoop
			,	@FullloadYears	= @FullloadYears
			,	@TEMPLoeschen	= @TEMPLoeschen
			,	@MaxDelay		= @MaxDelay
			,	@SQL_TableTargetDB		= @SQL_TableTargetDB
			,	@SQL_TableTargetSchema	= @SQL_TableTargetSchema

			--Join: Falldaten_BasisCube 00:01:36
			--Select * from Analysen.dbo.Falldaten_Aenderungshistorie where Fallnummer in (19925899,10414678) 
			--Select * from Falldaten_BasisCube where Fallnummer in (19925899)  AbrechnungID in (27888' or Fallnummer in (17523841,17574336) 
			--Select * from Fallzusammenfuehrung_Fall where fallid in (10000010010414678,10000010019925899,10000010017574336) 

			--Declare @TEMPPraefix as nvarchar(100); Declare @TEMPLoeschen as int; Declare @SQL_TableTargetDB as nvarchar(200); Declare @SQL_TableTargetSchema as nvarchar(200); Declare @SQL as nvarchar(max); Declare @SQL1 as nvarchar(max); Declare @SQL2 as nvarchar(max); Set @SQL_TableTargetDB='Analysen'; Set @SQL_TableTargetSchema='dbo'; Set @TEMPLoeschen=0; Set @TEMPPraefix=62944979; DECLARE @SQL_Variable1 as nvarchar(500)
			SET @SQL_Variable1=concat('left join ', @SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Falldaten_Merkmale t100 on |x|FallID=t100.FallID')
			
			Execute dbo.TabJoin
				@TEMPLoeschen=@TEMPLoeschen,@TEMPPraefix=@TEMPPraefix,@MaxDelay=@MaxDelay,
				@SQL_Table1_SourceDB	=@SQL_TableTargetDB, @SQL_Table1_SourceSchema =@SQL_TableTargetSchema,	
				@SQL_Table1_SourceName  ='Falldaten_Aenderungshistorie',--	@SQL_Table1_SourceWhere ='|x|FallID in (''10000010016338251'',''10000010016349533'',''10000010010414678'',''10000010019925899'',''10000010017574336'')',
				@SQL_Table2_SourceName	='Fallzusammenfuehrung_Fall',		@SQL_Table1_Connect_ID2 ='|x|FallID',		@SQL_Table2_Connect_ID ='|x|FallID_Alt',	@SQL_TableTargetRowID2 ='|x|RowID_Fallzusammenfuehrung_Fall', @SQL_Use_Table2_ID=1,
				@SQL_Table3_SourceName	='Patienten_Aenderungshistorie',	@SQL_Table1_Connect_ID3 ='|x|PatientenID',	@SQL_Table3_Connect_ID ='|x|PatientenID',	@SQL_TableTargetRowID3 ='|x|RowID_Patienten', 
				@SQL_TableTargetName	='Falldaten_BasisCube',  
				@SQL_TableTargetDefinition1='
				isnull(t2.FallID,t1.FallID)				as FallID
				,isnull(t2.Fallnummer,t1.Fallnummer)	as Fallnummer
				,t1.Fallnummer as Fallnummer_Alt
				,t1.FallID as FallID_Alt
				,t1.PatientenID
				,t3.Geschlecht
				,t3.Geburtsdatum
				,t1.Fall_ist_Auslandsfall
				,t2.AbrechnungID

				,Case when t2.Fall_ist_fuehrend=1		then 1
					  when t2.Fall_ist_fuehrend=0		then 2
					  when t2.Fallnummer is null		then 0 
				  end Fallzusammenfuehrung_Typ

				,Case when t2.Fall_ist_fuehrend=1	then ''Führender Abrechnungsfall''
					  when t2.Fall_ist_fuehrend=0	then ''Nicht führender Abrechnungsfall''
					  when t2.Fallnummer is null	then ''keine Fallzusammenführung''
				  end Fallzusammenfuehrung_Typ_Text

				 ,t2.Grund as Fallzusammenfuehrung_Grund
				 ,t2.Grund_KurzText as Fallzusammenfuehrung_Grund_KurzText

 				 ,Case when t2.Fallnummer=t1.Fallnummer	and len(t2.AbrechnungID)>0
					   then sum(t1.Fall_Tage_ohne_Berechnung_Pflege) over (partition by t2.AbrechnungID, t0.Zeitstempel_von1) 
					   else t1.Fall_Tage_ohne_Berechnung_Pflege
				  end Fall_Tage_ohne_Berechnung_Pflege
				 ,t1.Fall_Tage_ohne_Berechnung_Pflege as Fall_Tage_ohne_Berechnung_Pflege_Alt

				 ,Case when t2.Fallnummer=t1.Fallnummer	and len(t2.AbrechnungID)>0
					   then sum(t1.Fall_Tage_ohne_Berechnung_MD) over (partition by t2.AbrechnungID, t0.Zeitstempel_von1) 
					   else t1.Fall_Tage_ohne_Berechnung_MD
				  end Fall_Tage_ohne_Berechnung_MD
				 ,t1.Fall_Tage_ohne_Berechnung_MD as Fall_Tage_ohne_Berechnung_MD_Alt

				 ,t1.Fall_Art
				 ,t1.Fall_Art_KurzText
				 ,t1.Fall_Behandlungskategorie
				 ,t1.Fall_Abrechnung_Kennzeichen
				 ,t1.Fall_hat_Statistiksperre
				 ,t1.Fall_hat_Fakturasperre
				 ,t1.Fall_hat_Status_nach_MD_Verfahren
				 ,t1.Fall_Status
				 ,t1.Fall_Typ
				 ,isnull(t100.Fall_Merkmal,0) as Fall_Merkmal 
				 ',
				 @SQL_TableTargetWhere='',--'isnull(t2.Fall_ist_fuehrend,1)=1',
				 @SQL_TableTargetJoin=@SQL_Variable1,
				 @SQL_TableTargetID='|x|FallID'
				 ;

			Set @SQL_PostProcessing1 = CONCAT('
			Delete ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Falldaten_BasisCube 
			where Fallzusammenfuehrung_Typ=2');

			print @SQL_PostProcessing1
			exec(@SQL_PostProcessing1)


		End
end;

