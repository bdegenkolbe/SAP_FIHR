USE Analysen
GO

/*
exec [UpdateBaseTable_SETNODE_Aenderungshistorie] @Ladeverfahren='FN' , @TEMPLoeschen=0, @TEMPPraefix=387129222, @PreProcessing=1, @MainProcessing=1, @PostProcessing=0
SELECT * FROM Analysen.[dbo].HierarchieISH_BasisCube
SELECT * FROM [Replicate].[sap].[SETNODE] WHERE CONCAT(MANDT, SETCLASS, SUBCLASS, SETNAME, LINEID) = '1000103 CA_FAKU.230000000002'
SELECT * FROM [Replicate].[sap].[SETNODE__ct__bak] WHERE CONCAT(MANDT, SETCLASS, SUBCLASS, SETNAME, LINEID) = '1000103 CA_FAKU.230000000002' ORDER BY header__timestamp DESC
*/

CREATE OR ALTER PROC [dbo].[UpdateBaseTable_SETNODE_Aenderungshistorie]

	@DELAY int						=10,	--> Greift im Fasttrack auch die Daten n-Tage vor dem letzten Ladevorgang ab. 
	@DaysToFullLoad int				=7,		--> Aller wieviel Tage soll ein Fullload durchgeführt werden?
	@TestLoop nvarchar(100)			='',	--> bspw. 'Top 100' für 100 Testdatensätze
	@DeltaDays as int				=1,		--> Delta-Load beinhaltet n volle Tage 
	@FullloadYears as int			=5,		--> Jahre die als Fullload geladen werden sollen, 0=Delta-Load
	@Ladeverfahren as nvarchar(2)	='',	--> Wenn 'F' dann Fulload für alle geänderten Tabellen, wenn 'D' dann Deltaload, wenn 'FN' Fulload für alle Tabellen. Sonst entscheidet das Skript automatische über das Ladeverfahren anhand der Einstellungen
	@CDPOS_laden as int				=0,		--> Wenn 1 wird die CDPOS bei Änderungen geladen, wenn 2 wird CDPOS immer geladen, wenn 0 wird CDPOS nicht geladen
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
	@DropAllTables as int			=1,		--> Wenn 1 werden alle 

	@SQL_TableTargetDB as nvarchar(200)		= 'Analysen',	--> Übergabeparameter für DIAS
	@SQL_TableTargetSchema as nvarchar(200)	= 'dbo'		--> Übergabeparameter für DIAS

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
	DECLARE @SQL_TableSource_Where as nvarchar(max)

	DECLARE @SQL_TableTargetString as nvarchar(200)
	DECLARE @SQL_TableTargetFields as nvarchar(max)
	DECLARE @SQL_TableTargetID as nvarchar(200)
	DECLARE @SQL_TableTarget_Join as nvarchar(max)
	DECLARE @SQL_TableTarget_Definition as nvarchar(max)
	DECLARE @SQL_TableTarget_Definition1 as nvarchar(max)
	DECLARE @SQL_TableTargetUpDate as nvarchar(500)
	DECLARE @SQL_TableTargetCreateDate as nvarchar(500)
	DECLARE @SQL_TableTargetStornoDate as nvarchar(500)
	DECLARE @SQL_TableTargetStornoFlag as nvarchar(500)

	DECLARE @CDPOS_TableID as nvarchar(200)

	SET @SQL_TableSourceDB			= 'replicate'
	SET @SQL_TableSourceSchema		= 'sap'

	if @PreProcessing=1
		Begin
			Print 'PreProcessing'
		End

	if @MainProcessing=1
		Begin

			Print 'MainProcessing'

			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@DaysToFullLoad=@DaysToFullLoad,@TestLoop=@TestLoop,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,
					@CDPOS_laden=@CDPOS_laden,@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,@LastChangeOnDate=@LastChangeOnDate,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='SETLEAF',
					@SQL_TableSourceFields='MANDT,SETCLASS,SUBCLASS,SETNAME,VALSIGN,VALOPTION,VALFROM,VALTO,SEQNR',
					@SQL_TableSourceID='CONCAT(trim(|x|MANDT),trim(|x|SETCLASS),trim(|x|SUBCLASS),trim(|x|SETNAME),cast(|x|[LINEID] as int))',
					@SQL_TableSourceCreateDate='cast(''1.1.1998 00:00:00'' as datetime)',
					@SQL_TableSourceUpDate='cast(''1.1.1998 00:00:00'' as datetime)',
					@SQL_TableSourceStornoDate='cast(''31.12.2099 23:59:59'' as datetime)', 
					@SQL_TableSourceStornoFlag='0',	@ValidToStorno	= @ValidToStorno,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='HierarchieISH_Zuordnungen',
					@SQL_TableTargetID='|x|HierarchieISH_ZuordnungenID',
					@SQL_TableTargetDefinition1='
					CONCAT(trim(|x|MANDT),trim(|x|SETCLASS),trim(|x|SUBCLASS),trim(|x|SETNAME)) as HierarchieISH_KopfID
					,case when VALOPTION = ''BT'' then ''Wertebereich'' else ''Einzelwert'' end as HierarchieISH_Wertetyp
					,VALFROM as HierarchieISH_Wert_von
					,VALTO as HierarchieISH_Wert_bis
					,case when try_cast(VALFROM as bigint)>0 then try_cast(VALFROM as bigint) else Null end as HierarchieISH_Zahlenwert_von
					,case when try_cast(VALTO as bigint)>0 then try_cast(VALTO as bigint) else Null end as HierarchieISH_Zahlenwert_bis
					,SEQNR as HierarchieISH_Sequenz
					',
					@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen

			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@DaysToFullLoad=@DaysToFullLoad,@TestLoop=@TestLoop,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,
					@CDPOS_laden=@CDPOS_laden,@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,@LastChangeOnDate=@LastChangeOnDate,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='SETHEADERT',
					@SQL_TableSourceFields='DESCRIPT',
					@SQL_TableSourceID='CONCAT(trim(|x|MANDT),trim(|x|SETCLASS),trim(|x|SUBCLASS),trim(|x|SETNAME))',
					@SQL_TableSourceCreateDate='cast(''1.1.1998 00:00:00'' as datetime)',
					@SQL_TableSourceUpDate='cast(''1.1.1998 00:00:00'' as datetime)',
					@SQL_TableSourceStornoDate='cast(''31.12.2099 23:59:59'' as datetime)', @SQL_TableSourceStornoFlag='0',	@ValidToStorno	= @ValidToStorno,
					@SQL_TableSource_Where='|x|LANGU=''D''',
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='HierarchieISH_Text',
					@SQL_TableTargetID='|x|HierarchieISH_KopfID',
					@SQL_TableTargetDefinition1='DESCRIPT as HierarchieISH_KurzText',
					@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen

			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@DaysToFullLoad=@DaysToFullLoad,@TestLoop=@TestLoop,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,
					@CDPOS_laden=@CDPOS_laden,@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,@LastChangeOnDate=@LastChangeOnDate,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='SETHEADER',
					@SQL_TableSourceFields='SETTYPE,XUNIQ,RVALUE,TABNAME,FIELDNAME,ROLLNAME',
					@SQL_TableSourceID='CONCAT(trim(|x|MANDT),trim(|x|SETCLASS),trim(|x|SUBCLASS),trim(|x|SETNAME))',
					@SQL_TableSourceCreateDate='case when year(try_cast(t1.CREDATE as datetime)) between 1990 and year(getdate())+1
															  then try_cast(t1.CREDATE as datetime)+try_cast(t1.CRETIME as datetime)	
															  else case when year(try_cast(t1.UPDDATE as date)) between 1990 and year(getdate())+1
																		then cast(t1.UPDDATE as datetime)+cast(t1.UPDTIME as datetime) 
																		else cast(''1.1.2010 00:00:00'' as datetime)
																   end
														 end',
					@SQL_TableSourceUpDate='case when year(try_cast(t1.UPDDATE as datetime)) between 1990 and year(getdate())+1 
															  then try_cast(t1.UPDDATE as datetime)+try_cast(t1.UPDTIME as datetime)	
															  else case when year(try_cast(t1.UPDDATE as date)) between 1990 and year(getdate())+1
																		then cast(t1.CREDATE as datetime)+cast(t1.CRETIME as datetime) 
																		else cast(''1.1.2010 00:00:00'' as datetime)
																   end
														 end',
					@SQL_TableSourceStornoDate='cast(''31.12.2099 23:59:59'' as datetime)', @SQL_TableSourceStornoFlag='0',	@ValidToStorno	= @ValidToStorno,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='HierarchieISH_Kopf',
					@SQL_TableTargetID='|x|HierarchieISH_KopfID',
					@SQL_TableTargetDefinition1='
					SETTYPE as HierarchieISH_Typ,
					case when XUNIQ =''X'' then 1 else 0 end as HierarchieISH_eindeutig
					,RVALUE as HierarchieISH_Beispielwert
					,TABNAME as HierarchieISH_Tabelle
					,FIELDNAME as HierarchieISH_Feld
					,ROLLNAME as HierarchieISH_Rolle
					',
					@CDPOS_TableID = '|x|OBJECTID',
					@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen

			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@DaysToFullLoad=@DaysToFullLoad,@TestLoop=@TestLoop,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,
					@CDPOS_laden=@CDPOS_laden,@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,@LastChangeOnDate=@LastChangeOnDate,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='SETNODE',
					@SQL_TableSourceFields='MANDT,SETCLASS,SUBCLASS,SETNAME,LINEID,SUBSETCLS,SUBSETSCLS,SUBSETNAME,SEQNR',
					@SQL_TableSourceID='CONCAT(trim(|x|MANDT),trim(|x|SETCLASS),trim(|x|SUBCLASS),trim(|x|SETNAME),cast(|x|[LINEID] as int))',
					@SQL_TableSourceCreateDate='cast(''1.1.1998 00:00:00'' as datetime)',
					@SQL_TableSourceUpDate='cast(''1.1.1998 00:00:00'' as datetime)',
					@SQL_TableSourceStornoDate='cast(''31.12.2099 23:59:59'' as datetime)', @SQL_TableSourceStornoFlag='0',	@ValidToStorno	= @ValidToStorno,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='HierarchieISH_Knoten',
					@SQL_TableTargetID='|x|HierarchieISH_KnotenID',
					@SQL_TableTargetDefinition1 = '
						CONCAT(trim(|x|MANDT),trim(|x|SETCLASS),trim(|x|SUBCLASS),trim(|x|SETNAME))  as HierarchieISH_KopfID
						,CONCAT(trim(|x|MANDT),trim(|x|SUBSETCLS),trim(|x|SUBSETSCLS),trim(|x|SUBSETNAME))  as HierarchieISH_ChildKopfID
						,[SETCLASS]				as HierarchieISH_Klasse
						,[SUBCLASS]				as HierarchieISH_Unterklasse
						,[SETNAME]				as HierarchieISH_Knoten
						,cast([LINEID] as int)	as HierarchieISH_Zeile
						,[SUBSETCLS]			as HierarchieISH_Child_Klasse
						,[SUBSETSCLS]			as HierarchieISH_Child_Unterklasse
						,[SUBSETNAME]			as HierarchieISH_Child_Knoten
						,cast([SEQNR] as int)	as HierarchieISH_Sequenz
						',
					@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen

				end

	if @PostProcessing=1
		Begin
			Print 'PostProcessing'

			/*
			SELECT *   FROM [Analysen].[dbo].HierarchieISH_Knoten where HierarchieISH_KnotenID ='1000103CA_FAKU.232' and Lastchangeondate=1 =2
			SELECT *   FROM [Analysen].[dbo].HierarchieISH_Kopf where HierarchieISH_KopfID ='1000103CA_FAKU.23'
			SELECT *   FROM [Analysen].[dbo].HierarchieISH_Text where HierarchieISH_KopfID ='1000103CA_FAKU.23'
			SELECT *   FROM [Analysen].[dbo].HierarchieISH_Zuordnungen where HierarchieISH_KnotenID ='1000103CA_FAKU.232'
			SELECT *   FROM [Analysen].[dbo].HierarchieISH_BasisCube where HierarchieISH_KnotenID ='1000103CA_FAKU.232' and HierarchieISH_Zeile=2
			*/
			--Declare @TEMPPraefix as nvarchar(100); Declare @TEMPLoeschen as int; Declare @SQL_TableTargetDB as nvarchar(200); Declare @SQL_TableTargetSchema as nvarchar(200); Declare @SQL as nvarchar(max); Declare @SQL1 as nvarchar(max); Declare @SQL2 as nvarchar(max); Set @SQL_TableTargetDB='Analysen'; Set @SQL_TableTargetSchema='dbo'; Set @TEMPLoeschen=0; Set @TEMPPraefix=387129222; 
			Execute dbo.TabJoin
				@TEMPLoeschen=@TEMPLoeschen, @TEMPPraefix=@TEMPPraefix, @SQL_TableTargetDB	=@SQL_TableTargetDB, @SQL_TableTargetSchema =@SQL_TableTargetSchema,	
				@SQL_Table1_SourceName  ='HierarchieISH_Knoten',		--@SQL_Table1_SourceWhere='HierarchieISH_KnotenID in (''10000006-GJAHR-IP.CCSS2'',''1000103CA_FAKU.232'')',
				@SQL_Table3_SourceName	='HierarchieISH_Text',			@SQL_Table1_Connect_ID3 ='|x|HierarchieISH_KopfID',		@SQL_Table3_Connect_ID ='|x|HierarchieISH_KopfID',		@SQL_TableTargetRowID3 ='|x|RowID_Text',
				@SQL_Table4_SourceName	='HierarchieISH_Text',			@SQL_Table1_Connect_ID4 ='|x|HierarchieISH_ChildKopfID',	@SQL_Table4_Connect_ID ='|x|HierarchieISH_KopfID',	@SQL_TableTargetRowID4 ='|x|RowID_Child_Text',
				@SQL_Table5_SourceName	='HierarchieISH_Kopf',			@SQL_Table1_Connect_ID5 ='|x|HierarchieISH_ChildKopfID',	@SQL_Table5_Connect_ID ='|x|HierarchieISH_KopfID',	@SQL_TableTargetRowID5 ='|x|RowID_Child_Kopf',	
				@SQL_Table6_SourceName	='HierarchieISH_Zuordnungen',	@SQL_Table1_Connect_ID6 ='|x|HierarchieISH_ChildKopfID',	@SQL_Table6_Connect_ID ='|x|HierarchieISH_KopfID',	@SQL_TableTargetRowID6 ='|x|RowID_Child_Zuordnung', @SQL_Table6_ID='HierarchieISH_ZuordnungenID', @SQL_Use_Table6_ID=1,

				@SQL_TableTargetName	='HierarchieISH_BasisCube',
				@SQL_TableTargetDefinition1='
						 t1.HierarchieISH_Klasse
						,t1.HierarchieISH_Unterklasse
						,t1.HierarchieISH_Knoten
						,t3.HierarchieISH_KurzText as HierarchieISH_Knoten_KurzText

						,t1.HierarchieISH_Child_Klasse
						,t1.HierarchieISH_Child_Unterklasse
						,t1.HierarchieISH_Child_Knoten
						,t4.HierarchieISH_KurzText as HierarchieISH_Child_KurzText
	
						,t1.HierarchieISH_Sequenz as HierarchieISH_Knoten_Sequenz

						,t5.HierarchieISH_Typ as HierarchieISH_Child_Typ
						,t5.HierarchieISH_eindeutig as HierarchieISH_Child_eindeutig
						,t5.HierarchieISH_Tabelle as HierarchieISH_Child_Tabelle
						,t5.HierarchieISH_Feld as HierarchieISH_Child_Feld
						,t5.HierarchieISH_Rolle as HierarchieISH_Child_Rolle
						
						,t6.HierarchieISH_Wertetyp
						,t6.HierarchieISH_Wert_von
						,t6.HierarchieISH_Wert_bis
						,t6.HierarchieISH_Zahlenwert_bis
						,t6.HierarchieISH_Zahlenwert_von
						,t6.HierarchieISH_Sequenz as HierarchieISH_Zuordnung_Sequenz
				 ' ;
		End
end;


