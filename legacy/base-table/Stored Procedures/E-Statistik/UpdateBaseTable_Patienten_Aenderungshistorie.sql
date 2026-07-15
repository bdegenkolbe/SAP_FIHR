USE Analysen
GO

--exec dbo.UpdateBaseTable_Patienten_Aenderungshistorie @Ladeverfahren = 'D', @PreProcessing=0, @MainProcessing=1, @PostProcessing=1, @TEMPPraefix=102194899, @CDPOS_laden=1, @TEMPLoeschen=0, @MaxDelay=3

CREATE or ALTER PROC dbo.UpdateBaseTable_Patienten_Aenderungshistorie

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

	@SQL_TableSource_Where as nvarchar(max) = '', --> Filter der Originaltabelle ohne Where-Befehl --> 'cast(|x|PATNR as bigint) in (4374641)'
	@SQL_TableTargetDB as nvarchar(200)		= 'Analysen',	--> Übergabeparameter für DIAS
	@SQL_TableTargetSchema as nvarchar(200)	= 'dbo',		--> Übergabeparameter für DIAS
	@SQL_TableTargetName as nvarchar(200)	= 'Patienten_Aenderungshistorie'	--> Übergabeparameter für DIAS

as
Begin

	PRINT 'Starte Skripabarbeitung'
	Print @LastChangeOnDate
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
	SET @SQL_TableSourceName		= 'NPAT'
	SET @SQL_TableSourceString		=  Concat(@SQL_TableSourceDB,'.',@SQL_TableSourceSchema,'.',@SQL_TableSourceName)
	SET @SQL_TableSourceID			= 'CONCAT(|x|MANDT,|x|PATNR)'
	SET @SQL_TableSourceFields		= 'MANDT,GSCHL,TITEL,VNAME,NNAME,GBDAT,GLAND,TODKZ,TODDT,TODZT,TODUR,ANRED,FAMST,KONFE,NATIO,LAND,PSTLZ,ORT,STRAS,GEBIE'
	SET @SQL_TableSourceUpDate		= 'case when year(|x|UPDAT) between 1990 and year(getdate()) then try_cast(|x|UPDAT as datetime)+cast(''23:59:59'' as datetime) else try_cast(|x|ERDAT as datetime) end'
	SET @SQL_TableSourceCreateDate  = 'try_cast(|x|ERDAT as datetime)'
	SET @SQL_TableSourceStornoDate  = 'case when year(|x|STDAT) between 1990 and year(getdate()) and |x|STORN=''X'' then try_cast(|x|STDAT as datetime)+cast(''23:59:59'' as datetime) else cast(''31.12.2099 23:59:59'' as datetime) end'
	SET @SQL_TableSourceStornoFlag  = 'case when |x|STORN=''X'' then 1 else 0 end'
	SET @SQL_TableSourceStornoField = '|x|STORN'
	SET @SQL_TableSource_Where		= ''
	SET @SQL_TableTargetString		= Concat(@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.',@SQL_TableTargetName,'')
	SET @SQL_TableTargetID			= '|x|PatientenID'
	SET @CDPOS_TableID				= 'concat(|x|MANDANT,|x|OBJECTID)'

	SET @SQL_TableTargetDefinition1 = '
					Case when ANRED in (''01'',''04'',''07'') then ''Herr'' 
						 when ANRED in (''02'',''05'',''06'') then ''Frau'' 
						 else '''' end as Anrede
					,TITEL as Titel
					,VNAME as Vorname
					,NNAME as Nachname
					,case GSCHL when 1 then ''männlich'' 
								when 2 then ''weiblich''
								else ''Sonstiges'' end as Geschlecht
					,cast(GBDAT as date) as Geburtsdatum
					,GLAND as Geburtsland
					,CONCAT(|x|MANDT,|x|GLAND) as GeburtslandID
					,case Trim(FAMST) when ''0'' then ''ledig''
									  when ''1'' then ''verheiratet''
									  when ''2'' then ''verwitwet''
									  when ''3'' then ''geschieden''
									  when ''5'' then ''getrennt''
									  else ''unbekannt'' end as Familienstand
					,case when TODKZ =''X'' then 1 else 0 end as Patient_ist_verstorben
					,try_cast(TODDT as datetime) + try_cast(TODZT as datetime) as Patient_ist_verstorben_am 
					,STRAS as Wohnort_Strasse
					,ORT as Wohnort_Ort
					,PSTLZ as Wohnort_Postleitzahl
					,CONCAT(|x|MANDT,|x|LAND)  as Wohnort_LandID
					,GEBIE as Wohnort_GebietsSchlüssel
					,CONCAT(|x|MANDT,|x|NATIO) as NationalitätID
					'

	if @PreProcessing=1
		Begin
			Print 'PreProcessing'
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

			--Select * from Patienten_Aenderungshistorie where PatientenID in ('10000010020205762')
			--Select * from Patienten_BasisCube_Test20240009 where FallID in ('10000010020205762','')

			--Declare @Ladeverfahren as nvarchar(100);Declare @TEMPPraefix as nvarchar(100); Declare @TEMPLoeschen as int; Declare @SQL_TableTargetDB as nvarchar(200); Declare @SQL_TableTargetSchema as nvarchar(200); Declare @SQL as nvarchar(max); Declare @SQL1 as nvarchar(max); Declare @SQL2 as nvarchar(max); Set @SQL_TableTargetDB='Analysen'; Set @SQL_TableTargetSchema='dbo'; Set @TEMPLoeschen=1; Set @TEMPPraefix=62944979; DECLARE @SQL_Variable1 as nvarchar(500); SET @SQL_Variable1=concat('left join ', @SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Falldaten_Merkmale t99 on |x|FallID=t99.FallID'); SET  @Ladeverfahren='D'
			Execute dbo.TabJoin
				@Ladeverfahren=@Ladeverfahren,@TEMPLoeschen=@TEMPLoeschen,@TEMPPraefix=@TEMPPraefix,@MaxDelay=@MaxDelay,
				@SQL_Table1_SourceDB	=@SQL_TableTargetDB, @SQL_Table1_SourceSchema =@SQL_TableTargetSchema,	
				@SQL_Table1_SourceName	='Falldaten_Aenderungshistorie', @SQL_TableTargetRowID1 ='|x|RowID_Fall',	--@SQL_Table1_SourceWhere='FallID=''10000010020240009''',
				@SQL_Table2_SourceName	='Patienten_Aenderungshistorie', @SQL_Table1_Connect_ID2 ='|x|PatientenID',	@SQL_Table2_Connect_ID ='|x|PatientenID',		@SQL_TableTargetRowID2 ='|x|RowID_Patienten', @SQL_Table2_SourceJoinTyp='INNER',
				@SQL_TableTargetName	='Patienten_BasisCube',  
				@SQL_TableTargetDefinition1=' 
					      t2.PatientenID
						  ,t2.Anrede
						  ,t2.Titel
						  ,t2.Vorname
						  ,t2.Nachname
						  ,t2.Geschlecht
						  ,t2.Geburtsdatum
						  ,t2.Geburtsland
						  ,t2.GeburtslandID
						  ,t2.Familienstand
						  ,t2.Patient_ist_verstorben
						  ,t2.Patient_ist_verstorben_am
						  ,t2.Wohnort_Strasse
						  ,t2.Wohnort_Ort
						  ,t2.Wohnort_Postleitzahl
						  ,t2.Wohnort_LandID
						  ,t2.Wohnort_GebietsSchlüssel
						  ,t2.NationalitätID
						  ,t1.FallID'
				 ;

		End
end;

