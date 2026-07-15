USE [Analysen]
GO

--exec dbo.UpdateBaseTable_Leistungen_Aenderungshistorie @Ladeverfahren = 'FN', @PreProcessing=1, @MainProcessing=0, @PostProcessing=0, @TEMPPraefix=216106645
--exec dbo.UpdateBaseTable_Leistungen_Aenderungshistorie @Ladeverfahren = 'FN', @PreProcessing=0, @MainProcessing=1, @PostProcessing=0, @TEMPLoeschen=1, @CDPOS_laden=0, @TestLoop='Top 1000', @SQL_TableSource_Where = 'cast(|x|FALNR as bigint)=17523841 or cast(|x|LNRLS as bigint) in (155534180,156472563,161702821,162064373,162076407,20430305,116957049,116957050,9000000013,129721981,130375103)'
--Select * from Analysen.dbo.Leistungen_Aenderungshistorie where Fallnummer=17771344
CREATE or ALTER PROC dbo.UpdateBaseTable_Leistungen_Aenderungshistorie
	
	@DELAY int						=2,	--> Greift im Fasttrack auch die Daten n-Tage vor dem letzten Ladevorgang ab. 
	@MaxDelay	as bigint			=0,		--> Maximale Verzögerung des letzten Aktualisierung einer Quelltabelle in Minuten. Insofern 0 oder negative Zahlen verwendet werden, bezieht sich die Verzögerung auf Tage. (0 die Aktualisierung muss von heute sein, -1 die Aktualisierung muss von gestern sein)
	@DaysToFullLoad int				=7,		--> Aller wieviel Tage soll ein Fullload durchgeführt werden?
	@TestLoop nvarchar(100)			='',	--> bspw. 'Top 100' für 100 Testdatensätze
	@DeltaDays as int				=1,		--> Delta-Load beinhaltet n volle Tage 
	@FullloadYears as int			=5,		--> Jahre die als Fullload geladen werden sollen, 0=Delta-Load
	@Ladeverfahren as nvarchar(2)	='',	--> Wenn 'F' dann Fulload, wenn 'D' dann Deltaload, Sonst entscheidet das Skript automatische über das Ladeverfahren anhand der Einstellungen
	@CDPOS_laden as int				=0,		--> Wenn 1 wird die CDPOS bei Änderungen geladen, wenn 2 wird CDPOS immer geladen, wenn 0 wird CDPOS nicht geladen
	@LastChangeFromTarget as int	=0,		--> Wenn 1 wird der letzte Änderungszeitpunkt aus der TargetTabelle berechnet - langsam/0=Änderungszeitpunkt wird aus den SYS-Tabellen berechnet
	@HashAbgleich_ct as int			=1,		--> 1=Nur relevanten Änderungen in den ct Tabellen werden mit einem HASH über die ausgewählten Spalten verarbeitet/0=keine Hash-Prüfung im ersten Schritt
	@Historisierung as int			=0,		--> 1=Historisierte Werte aus CT-Tabellen und der CDPOS werden abgefragt / 0=keine historisierten Werte
	@PreProcessing as int			=1,		--> 1=Vorprozesse werden ausgeführt
	@MainProcessing as int			=1,		--> 1=Hauptprozess wird ausgeführt
	@PostProcessing as int			=1,		--> 1=Nachprozesse werden ausgeführt
	@TEMPPraefix as nvarchar(100)	='New',	--> 'New' wird eine neue TempID für alle Temptabellen vergeben. Insofern ein Wert für @TEMPPraefix=108512190 angegeben wird, wird dieser Wert für alle Temp-Tabellen verwendet.
	@TEMPLoeschen as int			=1,		--> 1=Tempdateien werden gelöscht
	@StartStep as varchar(10)		='',	--> Startet mit Prozessschritt bspw. 'XP270'
	@LastChangeOnDate as int		=1,		--> Wenn 1 werden nur die letzten Änderungen eines Tages ausgewertet. Wenn 0 werden alle datensätze ausgewertet.
	@ValidToStorno as int			=1,		--> Wenn 1 wird der Gültigkeitszeitraum des Datensatzes zum Stornozeitpunkt beendet (Standard). Wenn 0 ist der Datensatz auch nach dem Stornozeitpunkt gültig.
	@ValidBeforeStorno as int		=1,		--> Wenn 1 sind alle Datensätze eine Zeiteinheit vor einem Storno gültig (Standard). Wenn 0 sind alle Datensätze genau bis zum Storno gültig.

	@SQL_TableSource_Where as nvarchar(max) = '', --> Filter der Originaltabelle ohne Where-Befehl -->  'cast(|x|LNRLS as bigint) in (20380404,20430305,116957049,116957050,9000000013)'
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
	DECLARE @SQL3 as nvarchar(max)

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
						@LogTableName='Leistungen',
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
			SET @StepPraefix='Pre20'
			SET @StepText= Concat('','UpdateBaseTable [Leistung_Katalog_Eigenschaften]')
			--NTPK: Leistung_Katalog_Eigenschaften
			--Select * from Leistung_Katalog_Eigenschaften where Leistung_Katalog_LeistungID like '%TE-T-KLEI1'
			--Select * from replicate.sap.NTPK where TALST='ZE01.01'
			--Select distinct bform from replicate.sap.ntpk
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=0,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='NTPK',
					@SQL_TableSourceFields='MANDT,EINRI,TARIF,TALST,TGRKZ,TAGRU,BFORM,ABRKZ,LEINH,ZEITR,N1ADMLEI,N1ANFOR,N1DAUER,N1ERBR,N1EXTER,N1MEDLEI,N1PFLLEI,ENTGA,HCOKZ,OTYPL,ENTKY,ENZKY,ENTG2,KTRKZ,ABWRL,GSCHL,AGELO,AGEHI,NOERF,FPTYP,EXPGR,OPTAB,PRADM,BEGDT,ENDDT',
					@SQL_TableSourceID='concat(|x|MANDT,|x|EINRI,|x|TARIF,|x|TALST)',
					@SQL_TableSourceCreateDate=	'case when year(|x|BEGDT) between 1990 and 2099 and try_cast(|x|BEGDT as datetime) is not null then cast(|x|BEGDT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end ',
					@SQL_TableSourceUpDate=		'case when year(|x|BEGDT) between 1990 and 2099 and try_cast(|x|BEGDT as datetime) is not null then cast(|x|BEGDT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end ',
					@SQL_TableSourceStornoDate=	'case when year(|x|ENDDT) between 1990 and 2099 and try_cast(|x|ENDDT as datetime) is not null then cast(|x|ENDDT as datetime) + cast(''23:59:59'' as datetime) else cast(''31.12.2099 23:59:59'' as datetime) end ',
					@SQL_TableSourceStornoFlag=	'case when year(|x|ENDDT) between 1990 and 2099 and try_cast(|x|ENDDT as datetime) is not null then 1 else 0 end',
					@ValidToStorno	= 1,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Leistung_Katalog_Eigenschaften',
					@SQL_TableTargetID='|x|Leistung_Katalog_LeistungID',
					@SQL_TableTargetDefinition1='
					case when |x|PRADM = ''X'' then 1 else 0 end as Aufnahmeleistung
					,case when |x|ABRKZ = ''X'' then 1 else 0 end as Leistung_ist_abrechenbar 

					,case when len(trim(|x|ENTKY))>0 then |x|ENTKY else Null end as Leistung_Entgeltschluessel12
					,case when len(trim(|x|ENZKY))>0 then |x|ENZKY else Null end as Leistung_Entgeltschluessel3
					,case when len(trim(Concat(|x|ENTKY,|x|ENZKY,|x|ENTG2)))>0 then Concat(|x|ENTKY,|x|ENZKY,|x|ENTG2) else Null end as Leistung_Entgeltschluessel

					,case 	when try_cast(left(|x|ENTKY,1) as int) between 1 and 9 then ''DRG''
							when left(|x|ENTKY,1)  in (''A'',''B'',''C'',''D'',''E'',''F'') then ''PEPP''
							else Null end as Leistung_Entgeltsystem

					,case when |x|ENTKY in (''70'',''71'',''72'',''73'',''74'') then 
						case when try_cast(|x|ENZKY as int) between 1 and 8 then try_cast(|x|ENZKY as int) 
								when |x|ENZKY=''A'' then 1
								when |x|ENZKY=''C'' then 3
								when |x|ENZKY=''D'' then 4
								when |x|ENZKY=''H'' then 8
								else Null end
						else Null end as Leistung_Entgelt_Versorgungsart
					,case when |x|ENTKY in (''70'',''71'',''72'',''73'',''74'') then
						case |x|ENZKY 
							when ''1'' then ''Hauptabteilung''
							when ''2'' then ''Hauptabteilung und Beleghebamme''
							when ''3'' then ''Belegoperateur''
							when ''4'' then ''Belegoperateur und Beleganästhesist''
							when ''5'' then ''Belegoperateur und Beleghebamme''
							when ''6'' then ''Belegoperateur, Beleganästhesist und Beleghebamme''
							when ''7'' then ''Teilstationäre Versorgung (für teilstationäre DRG-Fallpauschalen)''
							when ''8'' then ''Belegarzt mit Honorarvertrag (§18 Abs. 3 KHEntgG)''
							when ''A'' then ''Hauptabteilung''
							when ''C'' then ''Belegoperateur''
							when ''D'' then ''Belegoperateur und Beleganästhesist''
							when ''H'' then ''Belegarzt mit Honorarvertrag (§18 Abs. 3 KHEntgG)''
         					else ''Sonstige: '' + |x|ENZKY end
						else Null end as Leistung_Entgelt_Versorgungsart_KurzText
					,case when len(trim(|x|ENTGA))>0 then |x|ENTGA else Null end as Leistung_EntgeltArt
					,case when LEN(trim(|x|ENTKY))>0 
						and LEN(trim(|x|ENZKY))>0 
						and LEN(trim(|x|ENTG2))>0  
						and |x|ABRKZ=''X'' then 1 else 0 end as Leistung_Abrechnung
					,case when tStatistik.Katalog is not null then tStatistik.Katalog
						else case t1.ENTKY
							when ''70'' then ''E1''
							when ''76'' then ''E2''
							when ''80'' then ''NUB''
							when ''A1'' then ''E11''
							when ''B1'' then ''E11''
							when ''C4'' then ''E12''
							when ''C5'' then ''E2''
							when ''86'' then ''E31''
							when ''C9'' then case when t1.ENZKY=''2'' then ''E32''
												  when t1.ENZKY=''1'' then ''E33''
												  else null end
							when ''85'' then ''E33''
						else 
							case when right(t1.ENTKY,1)=''C'' then ''NUB'' else Null end
						end	
					 end as Leistung_E_Statistik
					,case when tStatistik.Katalog is not null then 
						case when CHARINDEX(''DRG'', tStatistik.Bereich)>0 then ''DRG: '' else ''PEPP: '' end
						+ case when CHARINDEX(''E32'', tStatistik.Katalog)>0 then ''Aufstellung der Zusatzentgelte [E3.2]''
							   when CHARINDEX(''E2'',  tStatistik.Katalog)>0 then ''Zusatzentgelt [E2]''
							   when CHARINDEX(''NUB'',  tStatistik.Katalog)>0 then ''Entgelt für neue Untersuchungs- und Behandlungsmethoden [NUB]'' end
						else 
							case t1.ENTKY
								when ''70'' then ''DRG: Fallpauschalen [E1]''
								when ''76'' then ''DRG: Zusatzentgelt [E2]''
								when ''A1'' then ''PEPP: Pauschalisierte Tagesentgelte [E1.1] (Vollstationär)''
								when ''B1'' then ''PEPP: Pauschalisierte Tagesentgelte [E1.1] (Teilstationär)''
								when ''C4'' then ''PEPP: Ergänzende Tagesentgelte [E1.2]''
								when ''C5'' then ''PEPP: Zusatzentgelte [E2]''
								when ''86'' then ''DRG: fallbezogenen Entgelte [E3.1]''
								when ''C9'' then case when t1.ENZKY=''2'' then ''PEPP: individuelle Zusatzentgelte [E3.2]''
														when t1.ENZKY=''1'' then ''PEPP: individuelle tagesbezogenen Entgelte [E3.3]''
														else null end
								when ''85'' then ''DRG: tagesbezogenen Entgelte [E3.3]''
							else 
								case when right(t1.ENTKY,1)=''C'' then ''Entgelte für NUBs'' else Null end
							end	
						End as Leistung_E_Statistik_KurzText',
					@SQL_TableTargetDefinition2='
					,case |x|ENTKY 	
						when ''01'' then ''DRG: Tagesgleicher Pflegesatz für Allgemeine Psychiatrie, Kinder- und Jugendpsychiatrie, und Psychosomatik/Psychotherapie''
						when ''02'' then ''DRG: Ermäßigter Abteilungspflegesatz für Allgemeine Psychiatrie, Kinder- und Jugendpsychiatrie, und Psychosomatik/Psychotherapie nach § 14 Abs. 2 Satz 3 oder Abs. 7 Satz 2 BPflV1''
						when ''40'' then ''DRG: Zuschlag nach § 8 Abs. 3 BPflV bzw. § 8 Abs. 3 KHEntgG (Investitionszuschlag)''
						when ''41'' then ''DRG: Entgelt für vorstationäre Behandlung''
						when ''42'' then ''DRG: Entgelt für nachstationäre Behandlung''
						when ''43'' then ''DRG: Pflegesatz bei Beurlaubung''
						when ''44'' then ''DRG: Modellvorhaben nach § 24 BPflV bzw. § 26 BPflV (Altvorhaben)''
						when ''45'' then ''DRG: Wahlleistung Unterkunft (nur für Knappschaft)''
						when ''46'' then ''DRG: Zuschlag für Qualitätssicherung nach § 7 Absatz 1 Satz 1 Nr. 7 KHEntgG oder § 7 Satz 1 Nr. 3 BPflV''
						when ''47'' then ''DRG: Zu-und Abschlag nach § 7 Abs. 1 Satz 1 Nr. 4 KHEntgG bzw. § 7 Satz 1 Nr. 3 und Satz 2 BPflV und sonstiger Zu- und Abschlag''
						when ''48'' then ''DRG: DRG Systemzuschlag''
						when ''49'' then ''DRG: Abrechnungsergänzungen''
						when ''60'' then ''DRG: Sonderfall''
						when ''61'' then ''DRG: Entgelt für integrierte Versorgung nach § 140c SGB V''
						when ''62'' then ''DRG: Abschlag bei Entgelten für integrierte Versorgung nach § 140c SGB V''
						when ''63'' then ''DRG: Entgelt für Modellvorhaben nach § 63 SGB V''
						when ''65'' then ''DRG: Zusatzentgelt für DMP''
						when ''70'' then ''DRG: Fallpauschalen''
						when ''71'' then ''DRG: Entgelt bei Überschreiten der oberen GVD''
						when ''72'' then ''DRG: Abschlag bei Verlegungen''
						when ''73'' then ''DRG: Abschlag bei Nichterreichen der unteren GVD''
						when ''74'' then ''DRG: Entgelt für Pflegeerlös/Tag''
						when ''75'' then ''DRG: Zu- und Abschlag''
						when ''76'' then ''DRG: Zusatzentgelt''
						when ''78'' then ''DRG: Teilstationäre Leistung''
						when ''80'' then ''DRG: Entgelt für neue Untersuchungs- und Behandlungsmethoden''
						when ''81'' then ''DRG: Entgelt bei Überschreiten der oberen GVD für NUBs''
						when ''82'' then ''DRG: Abschlag bei Verlegung für NUBs''
						when ''83'' then ''DRG: Abschlag bei Nichterreichen der unteren GVD für NUBs''
						when ''84'' then ''DRG: Pflegeanteil für tages- oder fallbezogenes Entgelt''
						when ''85'' then ''DRG: Tagesbezogenes Entgelt''
						when ''86'' then ''DRG: Fallbezogenes Entgelt ''
						when ''87'' then ''DRG: Entgelt bei Überschreiten der oberen GVD für fallbezogen Entgelt''
						when ''88'' then ''DRG: Abschlag bei Verlegung für fallbezogene Entgelte''
						when ''89'' then ''DRG: Abschlag bei Nichterreichen der unteren GVD für fallbezogene Entgelte''
						when ''90'' then ''DRG: Qualitätsverträge''',
					@SQL_TableTargetDefinition3='
						when ''91'' then ''DRG: Übergangspflege''
							else case when left(|x|ENTKY,1) in (''A'',''B'',''C'',''D'') then 
									''PEPP:'' + Case left(|x|ENTKY,1) 
													when ''A'' then ''vollstationär-''
													when ''B'' then ''teilstationär-'' 
													when ''C'' then ''stationärer Behandlungsbereich-'' 
													when ''D'' then ''stationsäquivalenter Behandlungsbereich-'' 
													else '''' 
												end
											+ Case right(|x|ENTKY,1) 
													when ''1'' then ''Bewertete Entgelte''
													when ''2'' then ''Zuschlag nach Überschreiten OGVD'' 
													when ''3'' then ''Abschlag nach Unterschreiten UGVD'' 
													when ''4'' then ''Ergänzende Tagesentgelte'' 
													when ''5'' then ''Zusatzentgelte'' 
													when ''6'' then ''Zuschläge'' 
													when ''7'' then ''Abschläge'' 
													when ''8'' then ''individuelle Entgelte'' 
													when ''9'' then ''individuelle Zusatzentgelte'' 
													when ''A'' then ''Modellvorhaben'' 
													when ''B'' then ''Entgelte für regionale und strukturelle Besonderheiten'' 
													when ''C'' then ''Entgelte für NUBs'' 
													when ''D'' then ''Teilzahlungsentgelte'' 
													when ''E'' then ''gesonderte Entgelte - Belegärzte'' 
													when ''F'' then ''Entgelte für Integrierte Versorgung'' 
													when ''G'' then ''Bewertete PEPP-Entgelte bei stationsäquivalenter Behandlung'' 
													when ''H'' then ''Unbewertete PEPP-Entgelte bei stationsäquivalenter Behandlung''
													when ''U'' then ''Übergangspflege''
													when ''V'' then ''vorstationäre Behandlung''
													when ''N'' then ''nachstationäre Behandlung''
													else '''' 
											end
								else Null end
						end as Leistung_EntgeltTyp_KurzText
						,|x|BFORM as Leistung_Bewertungsformel 
									',
					@SQL_TableTarget_Join=' left join (
												SELECT
													[sector] AS [Leistung]
												,	[data_key] AS [Katalog]
												,	[value] AS [Bereich]
												FROM [Referenzdaten].[dbo].[zuordnungstabelle_record]
												WHERE [RECORD_SET_ID] = (SELECT TOP 1 [zuordnungstabelle_record] FROM [Referenzdaten].[dbo].[zuordnungstabelle_meta_record] WHERE [creation_time] = (SELECT MAX([creation_time]) FROM [Referenzdaten].[dbo].[zuordnungstabelle_meta_record]))
											) AS tStatistik on |x|TALST = tStatistik.Leistung',
					@CDPOS_laden=0, @CDPOS_TableID	= 'CONCAT(|x|MANDANT,|x|OBJECTID)'

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PreProcessing', @LogStepError=@Fehler 
Pre30:
			SET @StepPraefix='Pre30'
			SET @StepText= Concat('','UpdateBaseTable [Leistung_Katalog_SpaltenText]')
			--NTST: Leistung_Katalog_SpaltenText
			--Select * from replicate.sap.ntst
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=0,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='NTST',
					@SQL_TableSourceFields='MANDT,EINRI,TARIF,TALST,TASPA,TASBZ',
					@SQL_TableSourceID='concat(|x|MANDT,|x|EINRI,|x|TARIF,|x|TASPA) ',
					@SQL_TableSourceCreateDate=	'cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceUpDate=		'cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceStornoDate=	'cast(''31.12.2099 23:59:59'' as datetime)',
					@SQL_TableSourceStornoFlag=	'0',	@ValidToStorno	= 1, @ValidBeforeStorno=0,
					@SQL_TableSource_Where='|x|SPRAS=''D''',
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Leistung_Katalog_SpaltenText',
					@SQL_TableTargetID='|x|Leistung_Katalog_SpalteTextID',
					@SQL_TableTargetDefinition1='TASBZ as SpalteText',
					@CDPOS_laden=0, @CDPOS_TableID	= '';

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PreProcessing', @LogStepError=@Fehler 
Pre40:
			SET @StepPraefix='Pre40'
			SET @StepText= Concat('','UpdateBaseTable [Leistung_Katalog_FallPauschalen]')
			--NTPKD: Leistung_Katalog_FallPauschalen
			--Select * from replicate.sap.NTPKD where TALST='TE-T-KLEI1'
			--Select * from Leistung_Katalog_FallPauschalen where Leistung_Katalog_LeistungID like '%TE-T-KLEI1'
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='NTPKD',
					@SQL_TableSourceFields='MANDT,EINRI,TARIF,TALST,BEGDT,ENDDT,MVDH,MVDB,OGVDH,OGVDB,UGVDH,UGVDB,RUGVDH,RUGVDB,ROGVDH,ROGVDB,RABVH,RABVB,NOWAH,NOWAB,VERFPH,VERFPB,RPFLH,RPFLB,LOWER_H,LOWER_B',
					@SQL_TableSourceID='concat(|x|MANDT,|x|EINRI,|x|TARIF,|x|TALST,|x|ENDDT)',
					@SQL_TableSourceCreateDate=	'case when year(|x|BEGDT) between 1990 and 2099 and try_cast(|x|BEGDT as datetime) is not null then cast(|x|BEGDT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end ',
					@SQL_TableSourceUpDate=		'case when year(|x|ENDDT) between 1990 and 2099 and try_cast(|x|ENDDT as datetime) is not null then cast(|x|ENDDT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end ',
					@SQL_TableSourceStornoDate=	'cast(''31.12.2099 23:59:59'' as datetime)',
					@SQL_TableSourceStornoFlag=	0,
					@ValidToStorno	= 1, @ValidBeforeStorno=0,
					@SQL_TableSource_Where='',
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Leistung_Katalog_FallPauschalen',
					@SQL_TableTargetID='|x|Leistung_Katalog_FallPauschalenID',
					@SQL_TableTargetDefinition1='
					 concat(MANDT,EINRI,TARIF,TALST) as Leistung_Katalog_LeistungID
					,case when year(BEGDT) between 1990 and year(getdate())+2 and try_cast(BEGDT as datetime) is not null then cast(BEGDT as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end as Wert_gueltig_von
					,case when year(ENDDT) between 1990 and 2099 and try_cast(ENDDT as datetime) is not null then cast(ENDDT as datetime) + cast(''23:59:59'' as datetime) else cast(''31.12.2099 23:59:59'' as datetime) end as Wert_gueltig_bis
					,MVDH as MVD_Haupt
					,MVDB as MVD_Beleg
					,cast(OGVDH as int) as OGVD_Haupt
					,cast(OGVDB as int) as OGVD_Beleg
					,cast(UGVDH as int) as UGVD_Haupt
					,cast(UGVDB as int) as UGVD_Beleg
					,RUGVDH as BWR_UGVD_Haupt		
					,RUGVDB as BWR_UGVD_Beleg	
					,ROGVDH as BWR_OGVD_Haupt	
					,ROGVDB as BWR_OGVD_Beleg	
					,RABVH as BWR_Verlegung_Haupt
					,RABVB as BWR_Verlegung_Beleg
					,RPFLH as BWR_Pflege_Haupt
					,RPFLB as BWR_Pflege_Beleg
					,CASE when NOWAH=''X'' then 1 else 0 end as Wiederaufnahme_Haupt
					,CASE when NOWAB=''X'' then 1 else 0 end as Wiederaufnahme_Beleg
					,CASE when VERFPH=''X'' then 1 else 0 end as Verlegungspauschale_Haupt
					,CASE when VERFPB=''X'' then 1 else 0 end as Verlegungspauschale_Beleg			
					,CASE when LOWER_H=''X'' then 1 else 0 end as Absenkung_Haupt
					,CASE when LOWER_B=''X'' then 1 else 0 end as Absenkung_Beleg',		
					@CDPOS_laden=0, @CDPOS_TableID	= ''

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PreProcessing', @LogStepError=@Fehler 
Pre50:
			SET @StepPraefix='Pre50'
			SET @StepText= Concat('','UpdateBaseTable [Leistung_Katalog_Bezeichnung]')
			--NTPT: Leistung_Katalog_Bezeichnung
			--Select * from replicate.sap.NTPT
			--Select * from Leistung_Katalog_Bezeichnung
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=0,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='NTPT',
					@SQL_TableSourceFields='MANDT,EINRI,TARIF,TALST,KTXT1,KTXT2,KTXT3,BEGDT,ENDDT',
					@SQL_TableSourceID='concat(|x|MANDT,|x|EINRI,|x|TARIF,|x|TALST)',
					@SQL_TableSourceCreateDate=	'case when year(|x|BEGDT) between 1990 and 2099 and try_cast(|x|BEGDT as datetime) is not null then cast(|x|BEGDT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end ',
					@SQL_TableSourceUpDate=		'case when year(|x|ENDDT) between 1990 and 2099 and try_cast(|x|ENDDT as datetime) is not null then cast(|x|ENDDT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end ',
					@SQL_TableSourceStornoDate=	'case when year(|x|ENDDT) between 1990 and 2099 and try_cast(|x|ENDDT as datetime) is not null then cast(|x|ENDDT as datetime) + cast(''23:59:59'' as datetime) else cast(''31.12.2099 23:59:59'' as datetime) end ',
					@SQL_TableSourceStornoFlag=	'case when year(|x|ENDDT) between 1990 and 2099 and try_cast(|x|ENDDT as datetime) is not null then 1 else 0 end',
					@ValidToStorno	= 1, @ValidBeforeStorno=0,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Leistung_Katalog_Bezeichnung',
					@SQL_TableTargetID='|x|Leistung_Katalog_LeistungID',
					@SQL_TableTargetDefinition1='trim(concat(|x|KTXT1,|x|KTXT2,|x|KTXT3)) as Leistung_Katalog_KurzText',
					@CDPOS_laden=0, @CDPOS_TableID	= ''

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PreProcessing', @LogStepError=@Fehler 
Pre60:
			SET @StepPraefix='Pre60'
			SET @StepText= Concat('','UpdateBaseTable [Leistung_Katalog_Grundwerte]')
			--NTSP: Leistung_Katalog_Grundwerte
			--Select * from Leistung_Katalog_Grundwerte where Leistung_Katalog_LeistungID like '%TE-T-KLEI1'
			--Select * from replicate.sap.NTSP where TALST like '%TE-T-KLEI1'
			--Select * from replicate.sap.cdpos where tabname = 'NTSP'
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=0,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='NTSP',
					@SQL_TableSourceFields='MANDT,EINRI,TARIF,TALST,TASPA,TWERT,BEGDT,ENDDT',
					@SQL_TableSourceID='concat(|x|MANDT,|x|EINRI,|x|TARIF,|x|TALST,|x|TASPA,|X|BEGDT)',
					@SQL_TableSourceCreateDate=	'isnull(try_cast(|x|BEGDT as datetime),try_cast(|x|ERDAT as datetime))',
					@SQL_TableSourceUpDate=		'case when year(|x|UPDAT) between 1990 and 2099 then cast(|x|UPDAT as datetime) + cast(''23:59:59'' as datetime) else cast(|x|ERDAT as datetime) end ',
					@SQL_TableSourceStornoDate=	'case when year(|x|LODAT) between 1990 and 2099 then try_cast(|x|LODAT as datetime) + cast(''23:59:59'' as datetime) else cast(''31.12.2099 23:59:59'' as datetime) end ',
					@SQL_TableSourceStornoFlag=	'case when year(|x|LODAT) between 1990 and 2099 then 1 else 0 end' ,
					@SQL_TableSource_Where='TASPA in (1,3,8,9,15,16,17,18,19,20) and (try_cast(REPLACE(|x|TWERT,''-'','''') as int) >0 or LEN (Replace(REPLACE(|x|TWERT,''-'',''''),'' '',''''))>0)',
					@ValidToStorno	= 1, @ValidBeforeStorno=0,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Leistung_Katalog_Grundwerte',
					@SQL_TableTargetID='|x|Leistung_Katalog_SpaltenID',
					@SQL_TableTargetDefinition1='
					concat(|x|MANDT,|x|EINRI,|x|TARIF,|x|TALST) as Leistung_Katalog_LeistungID
					,concat(|x|MANDT,|x|EINRI,|x|TARIF,|x|TASPA) as Leistung_Katalog_SpalteTextID
					,|x|TASPA as SpalteNummer
					,|x|TARIF as Tarif
					,case when |x|TASPA between 15 and 20 then try_cast(|x|TASPA  as int)-14 else Null end as Versorgungsart
					,case when |x|TASPA between 15 and 16 then ''Hauptabteilung'' 
						  when |x|TASPA between 17 and 20 then ''Belegabteilung'' 
						else Null end as Abteilungsart
					,Case when try_cast(REPLACE(|x|TWERT,''-'','''') as int) >=0 then
							case when right(|x|TWERT,1)=''-'' then 
								-try_cast(LEFT(|x|TWERT,LEN(|x|TWERT)-1) as Float)
							else
								try_cast(|x|TWERT as float)
							end 
						else Null end /
						case when |x|TASPA between 15 and 20 then 1000 
							 when |x|TASPA in (1,8,9) then 100 
							 else 1 end
						as Wert
					,cast(TWERT as varchar(50)) as String
					,case when year(|x|BEGDT) between 1990 and year(getdate())+2 and try_cast(|x|BEGDT as datetime) is not null then cast(|x|BEGDT as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end as Wert_gueltig_von
					,case when year(|x|ENDDT) between 1990 and 2099 and try_cast(|x|ENDDT as datetime) is not null then cast(|x|ENDDT as datetime) + cast(''23:59:59'' as datetime) else cast(''31.12.2099 23:59:59'' as datetime) end as Wert_gueltig_bis					
					',
					@CDPOS_laden=0, @CDPOS_TableID	= 'concat(|x|MANDANT, left(|x|OBJECTID,len(|x|OBJECTID)-15), left(right(|x|OBJECTID,10),2))'

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PreProcessing', @LogStepError=@Fehler 
Pre70:
			SET @StepPraefix='Pre70'
			SET @StepText= Concat('','UpdateBaseTable [Leistung_PEPP_Bezugsgroesse]')
			--TNPEPP: Leistung_PEPP_Bezugsgroesse
			--Select * from Leistung_PEPP_Bezugsgroesse where Fachrichtung=2900
			--Select * from replicate.sap.TNPEPP
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=0,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='TNPEPP',
					@SQL_TableSourceFields='MANDT,EINRI,FACHR,BASENT,BEGDT,ENDDT',
					@SQL_TableSourceID='concat(|x|MANDT,|x|EINRI,|x|BEGDT)',
					@SQL_TableSourceCreateDate=	'case when year(|x|BEGDT) between 1990 and 2099 and try_cast(|x|BEGDT as datetime) is not null then cast(|x|BEGDT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end ',
					@SQL_TableSourceUpDate	  =	'case when year(|x|BEGDT) between 1990 and 2099 and try_cast(|x|BEGDT as datetime) is not null then cast(|x|BEGDT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end ',
					@SQL_TableSourceStornoDate=	'cast(''31.12.2099 23:59:59'' as datetime)',
					@SQL_TableSourceStornoFlag=	'0',
					@SQL_TableSource_Where='|x|FACHR=2900',
					@ValidToStorno	= 1, @ValidBeforeStorno=0,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Leistung_PEPP_Bezugsgroesse',
					@SQL_TableTargetID='|x|Leistung_PEPP_BezugsgroesseID',
					@SQL_TableTargetDefinition1='
					|x|BASENT as Bezugsgroesse
					,try_cast(|x|BEGDT as datetime) as Wert_gueltig_von
					,try_cast(|x|ENDDT as datetime) + cast(''23:59:59'' as datetime) as Wert_gueltig_bis',
					@CDPOS_laden=0, @CDPOS_TableID	= ''

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PreProcessing', @LogStepError=@Fehler 
Pre80:
			SET @StepPraefix='Pre80'
			SET @StepText= Concat('','UpdateBaseTable [Leistung_DRG_BasisWerte]')
			--TNDRG: Leistung_DRG_BasisWerte
			--Select * from Leistung_DRG_BasisWerte
			--Select * from replicate.sap.TNDRG
			--Select * from replicate.sap.cdpos where tabname='TNDRG'
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=0,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='TNDRG',
					@SQL_TableSourceFields='MANDT,EINRI,CAREVAL,BASER,BEGDT,ENDDT',
					@SQL_TableSourceID='concat(|x|MANDT,|x|EINRI,|x|BEGDT)',
					@SQL_TableSourceCreateDate=	'case when year(|x|BEGDT) between 1990 and 2099 and try_cast(|x|BEGDT as datetime) is not null then cast(|x|BEGDT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end ',
					@SQL_TableSourceUpDate=		'case when year(|x|BEGDT) between 1990 and 2099 and try_cast(|x|BEGDT as datetime) is not null then cast(|x|BEGDT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end ',
					@SQL_TableSourceStornoDate=	'cast(''31.12.2099 23:59:59'' as datetime)',
					@SQL_TableSourceStornoFlag=	'0',
					@SQL_TableSource_Where='',
					@ValidToStorno	= 1, @ValidBeforeStorno=0,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Leistung_DRG_BasisWerte',
					@SQL_TableTargetID='|x|Leistung_DRG_BasisWertID',
					@SQL_TableTargetDefinition1='
					|x|CAREVAL as Pflegeentgeltwert
					,|x|BASER as Landesbasisfallwert
					,|x|BEGDT as Wert_gueltig_von
					,|x|ENDDT as Wert_gueltig_bis
					',
					@CDPOS_laden=0, @CDPOS_TableID	= ''

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PreProcessing', @LogStepError=@Fehler 
Pre90:
			SET @StepPraefix='Pre90'
			SET @StepText= Concat('','UpdateBaseTable [Leistung_PEPP_Bewertungsrelationen]')
			--NTPKDPREL: Leistung_PEPP_Bewertungsrelationen
			--Select * from Leistung_PEPP_Bewertungsrelationen where PEPP='P23ET01.06'
			--Select * from replicate.sap.NTPKDPREL where TALST='P23ET01.06'
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=0,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='NTPKDPREL',
					@SQL_TableSourceFields='MANDT,EINRI,TARIF,TALST,VWDFROM,VWDTO,VWDREL,UPDAT',
					@SQL_TableSourceID='concat(|x|MANDT,|x|EINRI,|x|TARIF,|x|TALST,|x|VWDFROM)',
					@SQL_TableSourceCreateDate=	'case when year(|x|UPDAT) between 1990 and 2099 and try_cast(|x|UPDAT as datetime) is not null then cast(|x|UPDAT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end ',
					@SQL_TableSourceUpDate=		'case when year(|x|UPDAT) between 1990 and 2099 and try_cast(|x|UPDAT as datetime) is not null then cast(|x|UPDAT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end ',
					@SQL_TableSourceStornoDate=	'cast(''31.12.2099 23:59:59'' as datetime) ',
					@SQL_TableSourceStornoFlag=	'0',
					@SQL_TableSource_Where='',
					@ValidToStorno	= 1, @ValidBeforeStorno=0,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='Leistung_PEPP_Bewertungsrelationen',
					@SQL_TableTargetID='|x|Leistung_PEPP_BewertungsrelationenID',
					@SQL_TableTargetDefinition1='
					concat(|x|MANDT,|x|EINRI,|x|TARIF,|x|TALST) as Leistung_Katalog_LeistungID
					,|x|TALST as PEPP
					,cast(|x|VWDFROM as int)	as PEPP_VWD_von 
					,isnull(Lead(cast(t1.VWDFROM as int)-1) over (partition by concat(t1.MANDT,t1.EINRI,t1.TARIF,t1.TALST)  order by cast(t1.VWDFROM as int)),9999) as PEPP_VWD_bis
					,Rank() over (partition by concat(t1.MANDT,t1.EINRI,t1.TARIF,t1.TALST) order by cast(t1.VWDFROM as int)) as PEPP_Stufe
					,cast(|x|VWDREL as numeric(14,5)) as PEPP_RelGew',
					@CDPOS_laden=0, @CDPOS_TableID	= ''

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PreProcessing', @LogStepError=@Fehler 

		End

	if @MainProcessing=1
		Begin
			
Main10:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Main10'
			SET @StepText= Concat('','UpdateBaseTable [Leistungen_Aenderungshistorie]')		
			SET @SQL_TableSource_Join=Concat('left join ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Filter_Fallnummer  tFilter on cast(|x|FALNR as bigint)=tFilter.FALNR')
			SET @SQL_TableSource_Where=concat(@SQL_TableSource_Where,case when len(@SQL_TableSource_Where)>0 then ' and ' else '' end,'not(datediff(d,|x|ERDAT,|x|UPDAT)<2 and |x|STORN=''X'') and isnull(tFilter.FALNR,0)>0')

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
					@SQL_TableSourceName='NLEI',
					@SQL_TableSourceFields='MANDT,EINRI,LNRLS,FALNR,LFDBEW,LEIST,HAUST,ANFOE,ANPOE,ERBOE,IMENG,IBGDT,IBZT,IENDT,IEZT,TARAS,BEGKZ,HCOKZ,ENTKY,ENZKY,ENTG2,KALKZ,ENTGA,REFKY,USER2,NLKZA,ENTGAMB,STALS,ABRKZ',
					@SQL_TableSourceID='concat(|x|MANDT,|x|EINRI,|x|LNRLS)',
					@SQL_TableSourceCreateDate=	'case when year(|x|ERDAT)=101 then 
											try_cast(|x|IBGDT as datetime) + try_cast(|x|IBZT as datetime) 
									   else try_cast(|x|ERDAT as datetime) + cast(''00:00:00'' as datetime) end',
					@SQL_TableSourceUpDate=		'case when year(|x|UPDAT) between 1990 and year(getdate()) then 
											dateadd(d,1,try_cast(|x|UPDAT as datetime) + cast(''00:00:00'' as datetime))
									   else case when year(|x|ERDAT)=101 then 
												try_cast(|x|IBGDT as datetime) + try_cast(|x|IBZT as datetime) 
											else try_cast(|x|ERDAT as datetime) + cast(''00:00:00'' as datetime) end end',
					@SQL_TableSourceStornoDate=	'case when |x|STORN=''X'' then 
											case when year(|x|UPDAT) between 1990 and year(getdate()) then 
												dateadd(d,-1,try_cast(|x|UPDAT as datetime) + cast(''23:59:59'' as datetime))
										    else case when year(|x|ERDAT)=101 then try_cast(''31.12.2099 23:59:59'' as datetime)
												 else try_cast(|x|ERDAT as datetime) + cast(''23:59:59'' as datetime) end end
									   else try_cast(''31.12.2099 23:59:59'' as datetime) end',
					@SQL_TableSourceStornoFlag=	'case when |x|STORN=''X'' then 1 else 0 end', @SQL_TableSourceStornoField = '|x|STORN' ,
					@CDPOS_TableID	= 'left(Tabkey,17)',
					@SQL_TableTargetName='Leistungen_Aenderungshistorie',
					@SQL_TableTargetID='|x|LeistungID', 
					@SQL_TableTarget_Join=' left join (
							SELECT
								[sector] AS [Leistung]
							,	[data_key] AS [Katalog]
							,	[value] AS [Bereich]
							FROM [Referenzdaten].[dbo].[zuordnungstabelle_record]
							WHERE [RECORD_SET_ID] = (SELECT TOP 1 [zuordnungstabelle_record] FROM [Referenzdaten].[dbo].[zuordnungstabelle_meta_record] WHERE [creation_time] = (SELECT MAX([creation_time]) FROM [Referenzdaten].[dbo].[zuordnungstabelle_meta_record]))
						) AS tStatistik on |x|LEIST = tStatistik.Leistung',
					@SQL_TableTarget_Where		= '|x|Datensatz_gueltig_von<=|x|Datensatz_gueltig_bis',
					@SQL_TableTargetDefinition1='
	 case when |x|FALNR =0 then Null 
			else concat(|x|MANDT,|x|EINRI,|x|FALNR,|x|LFDBEW)	end								as BewegungID
	,case when |x|FALNR =0 then Null 
			else concat(|x|MANDT,|x|EINRI,|x|FALNR)	end											as FallID
	,try_cast(case when |x|FALNR =0 then Null else |x|FALNR end   as bigint)					as Fallnummer
	,try_cast(case when |x|FALNR =0 then Null else |x|LFDBEW end  as bigint)					as Bewegung_Nummer
	,try_cast(|x|LNRLS as bigint)																as Leistung_Nummer
	,try_cast(|x|LEIST as nvarchar(10))															as Leistung_Code
	,concat(|x|MANDT,|x|EINRI,|x|HAUST,|x|LEIST)												as Leistung_Katalog_LeistungID
	,try_cast(case when trim(|x|STALS)=''P'' then 1 else 0 end as int)							as Leistung_ist_geplant		
	,try_cast(case when len(trim(|x|ANFOE))>0 then |x|ANFOE else Null end as nvarchar(10))		as Leistung_anfordernde_OEFA
	,try_cast(case when len(trim(|x|ANPOE))>0 then |x|ANPOE else Null end as nvarchar(10))		as Leistung_anfordernde_OEPF
	,try_cast(case when len(trim(|x|ERBOE))>0 then |x|ERBOE else Null end as nvarchar(10))		as Leistung_erbringende_OEER
	,try_cast(|x|IMENG as int)																	as Leistung_Menge
	,try_cast(|x|TARAS as numeric(10,4))														as Leistung_Faktor
	,case when len(|x|ENTGAMB)>0 then right(|x|ENTGAMB,len(|x|ENTGAMB)-1) else Null end			as Leistung_Entgelt_ambulant
	,case when year(|x|IBGDT)<2099 
		then try_cast(|x|IBGDT as datetime)+try_cast(|x|IBZT as datetime) 
		else cast(''31.12.2099 23:59:59''  as datetime) end										as Leistung_Beginn
	,case when year(|x|IENDT)<2099 
		then try_cast(|x|IENDT as datetime)+try_cast(|x|IEZT as datetime) 
		else cast(''31.12.2099 23:59:59''  as datetime) end										as Leistung_Ende
	,case when len(trim(|x|REFKY))>0 then |x|REFKY else Null end								as Leistung_Referenz
	,case when CHARINDEX(''Kst'', |x|USER2) >0 then right(|x|USER2,8) else Null end				as Leistung_Kostenstelle 
	,try_cast(Concat(case when |x|NLKZA=''X'' then ''1'' else ''0'' end, 
			case when |x|HCOKZ=''X'' then ''1'' else ''0'' end, 
			case when |x|KALKZ=''X'' then ''1'' else ''0'' end) as varchar(3))					as Leistung_Kennzeichen',
					@SQL_TableTargetDefinition2	='	
	,case when len(trim(|x|ENTKY))>0 then |x|ENTKY else Null end as Leistung_Entgeltschluessel12
	,case when len(trim(|x|ENZKY))>0 then |x|ENZKY else Null end as Leistung_Entgeltschluessel3
	,case when len(trim(Concat(|x|ENTKY,|x|ENZKY,|x|ENTG2)))>0 then Concat(|x|ENTKY,|x|ENZKY,|x|ENTG2) else Null end as Leistung_Entgeltschluessel
	,case 	when try_cast(left(|x|ENTKY,1) as int) between 1 and 9 then ''DRG''
			when left(|x|ENTKY,1)  in (''A'',''B'',''C'',''D'',''E'',''F'') then ''PEPP''
			else Null end as Leistung_Entgeltsystem
	,case when |x|ENTKY in (''70'',''71'',''72'',''73'',''74'',''86'') then 
		case when try_cast(|x|ENZKY as int) between 1 and 8 then try_cast(|x|ENZKY as int) 
			when |x|ENZKY=''A'' then 1
			when |x|ENZKY=''C'' then 3
			when |x|ENZKY=''D'' then 4
			when |x|ENZKY=''H'' then 8
			else 0 end
		else 0 end as Leistung_Entgelt_Versorgungsart
	,case when |x|ENTKY in (''70'',''71'',''72'',''73'',''74'',''86'') then
		case |x|ENZKY 
			when ''1'' then ''Hauptabteilung''
			when ''2'' then ''Hauptabteilung und Beleghebamme''
			when ''3'' then ''Belegoperateur''
			when ''4'' then ''Belegoperateur und Beleganästhesist''
			when ''5'' then ''Belegoperateur und Beleghebamme''
			when ''6'' then ''Belegoperateur, Beleganästhesist und Beleghebamme''
			when ''7'' then ''Teilstationäre Versorgung (für teilstationäre DRG-Fallpauschalen)''
			when ''8'' then ''Belegarzt mit Honorarvertrag (§18 Abs. 3 KHEntgG)''
			when ''A'' then ''Hauptabteilung''
			when ''C'' then ''Belegoperateur''
			when ''D'' then ''Belegoperateur und Beleganästhesist''
			when ''H'' then ''Belegarzt mit Honorarvertrag (§18 Abs. 3 KHEntgG)''
         	else ''Sonstige: '' + |x|ENZKY end
		else Null end as Leistung_Entgelt_Versorgungsart_KurzText
	,case when len(trim(|x|ENTGA))>0 then |x|ENTGA else Null end as Leistung_EntgeltArt
	,case when LEN(trim(|x|ENTKY))>0 
		and LEN(trim(|x|ENZKY))>0 
		and LEN(trim(|x|ENTG2))>0  
		and |x|ABRKZ=''X'' then 1 else 0 end as Leistung_Abrechnung
	,case when tStatistik.Katalog is not null then tStatistik.Katalog
		else case t1.ENTKY
			when ''70'' then ''E1''
			when ''76'' then ''E2''
			when ''80'' then ''NUB''
			when ''A1'' then ''E11''
			when ''B1'' then ''E11''
			when ''C4'' then ''E12''
			when ''C5'' then ''E2''
			when ''86'' then ''E31''
			when ''C9'' then case when t1.ENZKY=''2'' then ''E32''
								  when t1.ENZKY=''1'' then ''E33''
								  else null end
			when ''85'' then ''E33''
		else 
			case when right(t1.ENTKY,1)=''C'' then ''NUB'' else Null end
		end	
	 end as Leistung_E_Statistik
	,case when tStatistik.Katalog is not null then 
		case when CHARINDEX(''DRG'', tStatistik.Bereich)>0 then ''DRG: '' else ''PEPP: '' end
		+ case when CHARINDEX(''E32'', tStatistik.Katalog)>0 then ''Aufstellung der Zusatzentgelte [E3.2]''
				when CHARINDEX(''E2'',  tStatistik.Katalog)>0 then ''Zusatzentgelt [E2]''
				when CHARINDEX(''NUB'',  tStatistik.Katalog)>0 then ''Entgelt für neue Untersuchungs- und Behandlungsmethoden [NUB]'' end
		else 
			case t1.ENTKY
				when ''70'' then ''DRG: Fallpauschalen [E1]''
				when ''76'' then ''DRG: Zusatzentgelt [E2]''
				when ''A1'' then ''PEPP: Pauschalisierte Tagesentgelte [E1.1] (Vollstationär)''
				when ''B1'' then ''PEPP: Pauschalisierte Tagesentgelte [E1.1] (Teilstationär)''
				when ''C4'' then ''PEPP: Ergänzende Tagesentgelte [E1.2]''
				when ''C5'' then ''PEPP: Zusatzentgelte [E2]''
				when ''86'' then ''DRG: fallbezogenen Entgelte [E3.1]''
				when ''C9'' then case when t1.ENZKY=''2'' then ''PEPP: individuelle Zusatzentgelte [E3.2]''
										when t1.ENZKY=''1'' then ''PEPP: individuelle tagesbezogenen Entgelte [E3.3]''
										else null end
				when ''85'' then ''DRG: tagesbezogenen Entgelte [E3.3]''
			else 
				case when right(t1.ENTKY,1)=''C'' then ''Entgelte für NUBs'' else Null end
			end	
		End as Leistung_E_Statistik_KurzText',
				 @SQL_TableTargetDefinition3='
		,case t1.ENTKY 	
				when ''01'' then ''DRG: Tagesgleicher Pflegesatz für Allgemeine Psychiatrie, Kinder- und Jugendpsychiatrie, und Psychosomatik/Psychotherapie''
				when ''02'' then ''DRG: Ermäßigter Abteilungspflegesatz für Allgemeine Psychiatrie, Kinder- und Jugendpsychiatrie, und Psychosomatik/Psychotherapie nach § 14 Abs. 2 Satz 3 oder Abs. 7 Satz 2 BPflV1''
				when ''40'' then ''DRG: Zuschlag nach § 8 Abs. 3 BPflV bzw. § 8 Abs. 3 KHEntgG (Investitionszuschlag)''
				when ''41'' then ''DRG: Entgelt für vorstationäre Behandlung''
				when ''42'' then ''DRG: Entgelt für nachstationäre Behandlung''
				when ''43'' then ''DRG: Pflegesatz bei Beurlaubung''
				when ''44'' then ''DRG: Modellvorhaben nach § 24 BPflV bzw. § 26 BPflV (Altvorhaben)''
				when ''45'' then ''DRG: Wahlleistung Unterkunft (nur für Knappschaft)''
				when ''46'' then ''DRG: Zuschlag für Qualitätssicherung nach § 7 Absatz 1 Satz 1 Nr. 7 KHEntgG oder § 7 Satz 1 Nr. 3 BPflV''
				when ''47'' then ''DRG: Zu-und Abschlag nach § 7 Abs. 1 Satz 1 Nr. 4 KHEntgG bzw. § 7 Satz 1 Nr. 3 und Satz 2 BPflV und sonstiger Zu- und Abschlag''
				when ''48'' then ''DRG: DRG Systemzuschlag''
				when ''49'' then ''DRG: Abrechnungsergänzungen''
				when ''60'' then ''DRG: Sonderfall''
				when ''61'' then ''DRG: Entgelt für integrierte Versorgung nach § 140c SGB V''
				when ''62'' then ''DRG: Abschlag bei Entgelten für integrierte Versorgung nach § 140c SGB V''
				when ''63'' then ''DRG: Entgelt für Modellvorhaben nach § 63 SGB V''
				when ''65'' then ''DRG: Zusatzentgelt für DMP''
				when ''70'' then ''DRG: Fallpauschalen''
				when ''71'' then ''DRG: Entgelt bei Überschreiten der oberen GVD''
				when ''72'' then ''DRG: Abschlag bei Verlegungen''
				when ''73'' then ''DRG: Abschlag bei Nichterreichen der unteren GVD''
				when ''74'' then ''DRG: Entgelt für Pflegeerlös/Tag''
				when ''75'' then ''DRG: Zu- und Abschlag''
				when ''76'' then ''DRG: Zusatzentgelt''
				when ''78'' then ''DRG: Teilstationäre Leistung''
				when ''80'' then ''DRG: Entgelt für neue Untersuchungs- und Behandlungsmethoden''
				when ''81'' then ''DRG: Entgelt bei Überschreiten der oberen GVD für NUBs''
				when ''82'' then ''DRG: Abschlag bei Verlegung für NUBs''
				when ''83'' then ''DRG: Abschlag bei Nichterreichen der unteren GVD für NUBs''
				when ''84'' then ''DRG: Pflegeanteil für tages- oder fallbezogenes Entgelt''
				when ''85'' then ''DRG: Tagesbezogenes Entgelt''
				when ''86'' then ''DRG: Fallbezogenes Entgelt ''
				when ''87'' then ''DRG: Entgelt bei Überschreiten der oberen GVD für fallbezogen Entgelt''
				when ''88'' then ''DRG: Abschlag bei Verlegung für fallbezogene Entgelte''
				when ''89'' then ''DRG: Abschlag bei Nichterreichen der unteren GVD für fallbezogene Entgelte''
				when ''90'' then ''DRG: Qualitätsverträge''
				when ''91'' then ''DRG: Übergangspflege''
				else case when left(t1.ENTKY,1) in (''A'',''B'',''C'',''D'') then 
						''PEPP:'' + Case left(t1.ENTKY,1) 
										when ''A'' then ''vollstationär-''
										when ''B'' then ''teilstationär-'' 
										when ''C'' then ''stationärer Behandlungsbereich-'' 
										when ''D'' then ''stationsäquivalenter Behandlungsbereich-'' 
										else '''' 
									end
								+ Case right(t1.ENTKY,1) 
										when ''1'' then ''Bewertete Entgelte''
										when ''2'' then ''Zuschlag nach Überschreiten OGVD'' 
										when ''3'' then ''Abschlag nach Unterschreiten UGVD'' 
										when ''4'' then ''Ergänzende Tagesentgelte'' 
										when ''5'' then ''Zusatzentgelte'' 
										when ''6'' then ''Zuschläge'' 
										when ''7'' then ''Abschläge'' 
										when ''8'' then ''individuelle Entgelte'' 
										when ''9'' then ''individuelle Zusatzentgelte'' 
										when ''A'' then ''Modellvorhaben'' 
										when ''B'' then ''Entgelte für regionale und strukturelle Besonderheiten'' 
										when ''C'' then ''Entgelte für NUBs'' 
										when ''D'' then ''Teilzahlungsentgelte'' 
										when ''E'' then ''gesonderte Entgelte - Belegärzte'' 
										when ''F'' then ''Entgelte für Integrierte Versorgung'' 
										when ''G'' then ''Bewertete PEPP-Entgelte bei stationsäquivalenter Behandlung'' 
										when ''H'' then ''Unbewertete PEPP-Entgelte bei stationsäquivalenter Behandlung''
										when ''U'' then ''Übergangspflege''
										when ''V'' then ''vorstationäre Behandlung''
										when ''N'' then ''nachstationäre Behandlung''
										else '''' 
								end
					else Null end
			end as Leistung_EntgeltTyp_KurzText'

			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='MainProcessing', @LogStepError=@Fehler 

		end

	if @PostProcessing=1
		Begin
			
Post10:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post10'
			SET @StepText= Concat('','TabJoin [Leistung_PEPP_Auswertung_Monat]')	
			--Leistung_PEPP_Auswertung_Monat 00:45
			--Select * from Leistung_PEPP_Auswertung_Monat where FallID in ('10000010016767768x','10000010018316883','10000010018154184') and Leistung_Katalog_LeistungID in ('100000101P23PK04A','')
			--Select * from Leistungen_Aenderungshistorie where Leistung_E_Statistik='E12'
			--Select * from Leistung_PEPP_Bewertungsrelationen where Leistung_Katalog_LeistungID='100000101P23ET01.06' 
			--Declare @TEMPPraefix as nvarchar(100); Declare @MaxDelay as int; Declare @TEMPLoeschen as int; Declare @SQL_TableTargetDB as nvarchar(200); Declare @SQL_TableTargetSchema as nvarchar(200); Declare @SQL as nvarchar(max); Declare @SQL1 as nvarchar(max); Declare @SQL2 as nvarchar(max); Set @SQL_TableTargetDB='Analysen'; Set @SQL_TableTargetSchema='dbo'; Set @TEMPLoeschen=0; Set @TEMPPraefix=62944979; SET @MaxDelay=-1
			Execute [dbo].[TabJoin] 
					@TEMPLoeschen=@TEMPLoeschen, @TEMPPraefix=@TEMPPraefix, @SQL_Table1_SourceDB	=@SQL_TableTargetDB, @SQL_Table1_SourceSchema =@SQL_TableTargetSchema, @MaxDelay=@MaxDelay,	
					@SQL_Table1_SourceName  ='Leistungen_Aenderungshistorie',		@SQL_Table1_ID ='|x|LeistungID',		@SQL_TableTargetRowID1 ='|x|RowID_Leistung',@SQL_Table1_SourceFields='|x|Leistung_Beginn,|x|Leistung_Ende,|x|Leistung_E_Statistik',		
					@SQL_Table1_SourceWhere='|x|Leistung_Abrechnung=1 and |x|Leistung_E_Statistik in (''E11'',''E12'')',-- and FallID in (''10000010016767768x'',''10000010018028158x'',''10000010018485590'')',-- and Leistung_Katalog_LeistungID in (''100000101P21P003B'','''')',					
					@SQL_Table2_SourceName	='Bewegungen_Verweildauer',				@SQL_Table1_Connect_ID2 ='|x|FallID',							@SQL_Table2_Connect_ID ='|x|FallID',						@SQL_TableTargetRowID2 ='|x|RowID_Verweildauer',				@SQL_Table2_SourceFields='|x|Verweildauer', @SQL_Table2_SourceJoinTyp='INNER',
					@SQL_Table3_SourceName	='Leistung_PEPP_Bewertungsrelationen',	@SQL_Table1_Connect_ID3 ='|x|Leistung_Katalog_LeistungID',		@SQL_Table3_Connect_ID ='|x|Leistung_Katalog_LeistungID',	@SQL_TableTargetRowID3 ='|x|RowID_PEPP_Bewertungsrelationen',	@SQL_Table3_SourceWhere='|xBase|Verweildauer between |x|PEPP_VWD_von and |x|PEPP_VWD_bis', @SQL_Table3_ID='|x|Leistung_PEPP_BewertungsrelationenID' , @SQL_Use_Table3_ID=1 , 
					@SQL_Table4_SourceName	='Bewegungen_Verweildauer_PEPP_Monat',	@SQL_Table1_Connect_ID4 ='|x|RowID_Verweildauer',				@SQL_Table4_Connect_ID ='|x|RowID_Bewegungen_Verweildauer',	@SQL_TableTargetRowID4 ='|x|RowID_Verweildauer_Monat',			@SQL_Table4_SourceWhere='|xBase|Leistung_E_Statistik  in (''E11'',''E12'') or |xBase|Leistung_Ende between |x|Kalkulationsmonat_von and |x|Kalkulationsmonat_bis',  @SQL_Use_Table4_ID=1 ,
					@SQL_TableTargetWhere	= '|x|RowID_Verweildauer>0 and |x|RowID_Verweildauer_Monat>0',-- and (t3.PEPP_RelGew is null and t1.Leistung_Katalog_LeistungID in (''100000101P19PF96Z'',''100000101P19PF04Z'',''100000101P20PF96Z'',''100000101P21PF96Z'',''100000101P21TK04Z'',''100000101P21PF02Z'',''100000101P22PF96Z'',''100000101P22PF04Z'',''100000101P23PF96Z'',''100000101P23PF04Z'',''100000101P24PF96Z''))',
					@SQL_TableTargetName	='Leistung_PEPP_Auswertung_Monat',@SQL_TableTargetID='|x|LeistungMonatID',
					@SQL_TableTargetDefinition1='
					concat(t1.LeistungID, t4.Kalkulationsmonat) as LeistungMonatID
					,t1.FallID, t1.LeistungID, t1.Leistung_Katalog_LeistungID, t1.Leistung_Menge, t1.Leistung_Faktor, t1.Leistung_E_Statistik, t1.Leistung_Beginn, t1.Leistung_Ende
					,t2.Aufnahme_am, t2.Entlassung_am
					,t3.PEPP_RelGew, t3.PEPP_Stufe, t4.Bezugsgroesse
					,t2.Belegungstage as Belegungstage_Gesamt
					,t2.Verweildauer as Verweildauer_Gesamt
					,t2.Fall_Tage_ohne_Berechnung_MD as Fall_Tage_ohne_Berechnung_MD_Gesamt
					,t4.Kalkulationsmonat, t4.Kalkulationsmonat_von, t4.Kalkulationsmonat_bis
					,case when t1.Leistung_E_Statistik=''E11'' then t3.PEPP_RelGew * t4.Verweildauer 
					      when t1.Leistung_E_Statistik=''E12'' then t3.PEPP_RelGew * t1.Leistung_Menge
						  else 0 end as PEPP_BWR_Monat
					,case when t1.Leistung_E_Statistik=''E11'' then t3.PEPP_RelGew * t4.Verweildauer   * t4.Bezugsgroesse
						  when t1.Leistung_E_Statistik=''E12'' then t3.PEPP_RelGew * t1.Leistung_Menge * t4.Bezugsgroesse
						  else 0 end as PEPP_Betrag_Monat
					,t4.Belegungstage as Belegungstage_Monat
					,t4.Verweildauer as Verweildauer_Monat 
					,Null as RowID_Auswertung
					';

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='MainProcessing', @LogStepError=@Fehler 

Post20:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post20'
			SET @StepText= Concat('','Zusammenfassung der Tabelle [Leistung_PEPP_Auswertung_Monat] in der Tabelle [Leistung_PEPP_Auswertung]')	
			--Declare @SQL_PostProcessing1 as nvarchar(Max); Declare @TEMPPraefix as nvarchar(100); Declare @TEMPLoeschen as int; Declare @SQL_TableTargetDB as nvarchar(200); Declare @SQL_TableTargetSchema as nvarchar(200); Declare @SQL as nvarchar(max); Declare @SQL1 as nvarchar(max); Declare @SQL2 as nvarchar(max); Set @SQL_TableTargetDB='Analysen'; Set @SQL_TableTargetSchema='dbo'; Set @TEMPLoeschen=1; Set @TEMPPraefix=62944979
			SET @SQL=CONCAT('
			Drop table if exists Leistung_PEPP_Auswertung; 
			select Row_Number() over (order by t1.LeistungID, Rang) as RowID
				,t1.FallID, t2.SchluesselID, t1.LeistungID, Leistung_Katalog_LeistungID, Leistung_E_Statistik, Leistung_Beginn, Leistung_Ende, t1.Leistung_Menge, t1.Leistung_Faktor
				,MAX(Bezugsgroesse) as PEPP_Bezugsgroesse
				,MAX(PEPP_RelGew)	as PEPP_RelGew
				,MAX(PEPP_Stufe)	as PEPP_Stufe
				,MAX(Verweildauer_Gesamt) as Verweildauer
				,SUM(PEPP_BWR_Monat) as PEPP_BWR
				,SUM(PEPP_Betrag_Monat) as PEPP_Betrag
				,Rang, 1 as LastChangeOnDate, Datensatz_gueltig_von, Datensatz_gueltig_bis
			into ', @SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Leistung_PEPP_Auswertung 
			from ', @SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Leistung_PEPP_Auswertung_Monat t1
				join (
						Select LeistungID, Row_Number() over (order by LeistungID) as SchluesselID
						from (Select distinct LeistungID from ', @SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Leistung_PEPP_Auswertung_Monat where LeistungID is not null) t
					) t2 on t1.LeistungID = t2.LeistungID 
			group by t1.FallID, t2.SchluesselID, t1.LeistungID, Leistung_Katalog_LeistungID, t1.Leistung_Menge, t1.Leistung_Faktor, Leistung_E_Statistik, Leistung_Beginn, Leistung_Ende, Rang, Datensatz_gueltig_von, Datensatz_gueltig_bis
			
			CREATE INDEX xRowID ON ', @SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Leistung_PEPP_Auswertung 	(RowID ASC) 
			CREATE INDEX xLeistungID ON ', @SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Leistung_PEPP_Auswertung 	(LeistungID ASC) 
			CREATE INDEX xFallID ON ', @SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Leistung_PEPP_Auswertung 	(FallID ASC) 
			')
			print (@SQL)
			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke

Post25:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post25'
			SET @StepText= Concat('','RowIDs der Tabelle [Leistung_PEPP_Auswertung] an die Tabelle [Leistung_PEPP_Auswertung_Monat] anbinden!')	
			--Declare @SQL_PostProcessing1 as nvarchar(Max); Declare @TEMPPraefix as nvarchar(100); Declare @TEMPLoeschen as int; Declare @SQL_TableTargetDB as nvarchar(200); Declare @SQL_TableTargetSchema as nvarchar(200); Declare @SQL as nvarchar(max); Declare @SQL1 as nvarchar(max); Declare @SQL2 as nvarchar(max); Set @SQL_TableTargetDB='Analysen'; Set @SQL_TableTargetSchema='dbo'; Set @TEMPLoeschen=1; Set @TEMPPraefix=62944979
			SET @SQL=CONCAT('
			Update ', @SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Leistung_PEPP_Auswertung_Monat
			SET RowID_Auswertung=t2.RowID
			from ', @SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Leistung_PEPP_Auswertung_Monat t1
				join ', @SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Leistung_PEPP_Auswertung t2 on 
				t1.FallID = t2.FallID and 
				t1.LeistungID = t2.LeistungID and 
				t1.Leistung_Katalog_LeistungID = t2.Leistung_Katalog_LeistungID and 
				t1.Leistung_Menge = t2.Leistung_Menge and 
				t1.Leistung_Faktor = t2.Leistung_Faktor and 
				t1.Leistung_E_Statistik = t2.Leistung_E_Statistik and 
				t1.Leistung_Beginn = t2.Leistung_Beginn and 
				t1.Leistung_Ende = t2.Leistung_Ende and 
				t1.Rang = t2.Rang and 
				t1.Datensatz_gueltig_von = t2.Datensatz_gueltig_von and 
				t1.Datensatz_gueltig_bis = t2.Datensatz_gueltig_bis 
			')
			print (@SQL)
			EXEC(@SQL+@SQL1+@SQL2);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

			if @Fehler>0
				goto Fehlermarke
Post30:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post30'
			SET @StepText= Concat('','Update der Tabelle [Admin_TabTree]')

			--Declare @SQL_PostProcessing1 as nvarchar(Max); Declare @TEMPPraefix as nvarchar(100); Declare @TEMPLoeschen as int; Declare @SQL_TableTargetDB as nvarchar(200); Declare @SQL_TableTargetSchema as nvarchar(200); Declare @SQL as nvarchar(max); Declare @SQL1 as nvarchar(max); Declare @SQL2 as nvarchar(max); Set @SQL_TableTargetDB='Analysen'; Set @SQL_TableTargetSchema='dbo'; Set @TEMPLoeschen=1; Set @TEMPPraefix=62944979
			Set @SQL = Concat('
			Delete ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_TabTree 
			where TargetTableDB=''',@SQL_TableTargetDB,''' and 
				  TargetTableSchema=''',@SQL_TableTargetSchema,''' and 
				  TargetTableName=''Leistung_PEPP_Auswertung'';

			Insert into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_TabTree
			Values ((SELECT isnull(MAX(RelationID),1) + 1 FROM ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_TabTree),
			''',@SQL_TableTargetDB,''',
			''',@SQL_TableTargetSchema,''',
			''Leistung_PEPP_Auswertung'',
			(Select Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Leistung_PEPP_Auswertung'',''U'')) ,
			''LeistungID'',
			''RowID_Leistung_PEPP_Auswertung'',
			Getdate(),
			(SELECT max(p.rows) as Zeilen
									FROM sys.tables AS tbl
									JOIN sys.indexes as i ON i.object_id = tbl.object_id
									JOIN sys.partitions as p ON p.object_id = i.object_id and p.index_id = i.index_id
									JOIN sys.allocation_units as a ON a.container_id = p.partition_id
									where tbl.object_id=Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Leistung_PEPP_Auswertung'',''U'')),
			(SELECT ISNULL(8 * SUM(CASE WHEN a.type <> 1 THEN a.used_pages WHEN p.index_id < 2 THEN a.data_pages ELSE 0 END),0.0) as Speicherplatz
									FROM sys.tables AS tbl
									JOIN sys.indexes as i ON i.object_id = tbl.object_id
									JOIN sys.partitions as p ON p.object_id = i.object_id and p.index_id = i.index_id
									JOIN sys.allocation_units as a ON a.container_id = p.partition_id
									where tbl.object_id=Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Leistung_PEPP_Auswertung'',''U'')),
			''',@SQL_TableTargetDB,''',
			''',@SQL_TableTargetSchema,''',
			''Leistung_PEPP_Auswertung_Monat'',
			(Select Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Leistung_PEPP_Auswertung_Monat'',''U'')),
			(Select Distinct TargetID from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Admin_TabTree where TargetObjectID=Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Leistung_PEPP_Auswertung_Monat'',''U'')),
			''RowID'',
			(Select modify_date from ',@SQL_TableTargetDB,'.sys.tables where object_id=Object_ID(''',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.Leistung_PEPP_Auswertung_Monat'',''U'')),
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
 Post40:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''
			SET @StepPraefix='Post40'
			SET @StepText= Concat('','TabJoin [Leistung_Pre_Basiscube]')	
			Execute [dbo].[TabJoin] 
					@SQL_Table1_SourceDB		= @SQL_TableTargetDB
				,	@SQL_Table1_SourceSchema	= @SQL_TableTargetSchema
				,	@Ladeverfahren				= @Ladeverfahren
				,	@TEMPPraefix				= @TEMPPraefix
				,	@TEMPLoeschen				= @TEMPLoeschen
				,	@MaxDelay					= @MaxDelay
				-- Tabelle 1 - Leistungen_Aenderungshistorie
				,	@SQL_Table1_SourceName		= 'Leistungen_Aenderungshistorie'
				,	@SQL_Table1_ID				= '|x|LeistungID'
				,	@SQL_TableTargetRowID1		= '|x|RowID_Leistung'
				,	@SQL_Table1_SourceFields	= '|x|Leistung_Beginn,|x|Leistung_Ende,|x|Leistung_Entgelt_Versorgungsart,|x|Leistung_E_Statistik,|x|Leistung_Entgeltsystem'
				,	@SQL_Table1_SourceWhere		= '|x|Leistung_Abrechnung=1 and |x|Leistung_EntgeltSystem in (''DRG'',''PEPP'')'
				-- Tabelle 2 - Bewegungen_Verweildauer
				,	@SQL_Table2_SourceName		= 'Bewegungen_Verweildauer'
				,	@SQL_Table1_Connect_ID2		= '|x|FallID'
				,	@SQL_Table2_Connect_ID		= '|x|FallID'
				,	@SQL_TableTargetRowID2		= '|x|RowID_Verweildauer'
				,	@SQL_Table2_SourceFields	= '|x|Aufnahme_am,|x|Entlassung_am'
				,	@SQL_Table2_SourceJoinTyp	= 'INNER'
				-- Tabelle 3 - Leistung_Katalog_Eigenschaften
				,	@SQL_Table3_SourceName		= 'Leistung_Katalog_Eigenschaften'
				,	@SQL_Table1_Connect_ID3		= '|x|Leistung_Katalog_LeistungID'
				,	@SQL_Table3_Connect_ID		= '|x|Leistung_Katalog_LeistungID'
				,	@SQL_TableTargetRowID3		= '|x|RowID_Katalog_Eigenschaften'
				,	@SQL_Table3_SourceFields	= '|x|Aufnahmeleistung'
				-- Tabelle 4 - Leistung_Katalog_Grundwerte - für Spalte "Leistung_Grundwert"
				,	@SQL_Table4_SourceName		= 'Leistung_Katalog_Grundwerte'
				,	@SQL_Table1_Connect_ID4		= '|x|Leistung_Katalog_LeistungID'
				,	@SQL_Table4_Connect_ID		= '|x|Leistung_Katalog_LeistungID'
				,	@SQL_TableTargetRowID4		= '|x|RowID_Grundwert'
				,	@SQL_Table4_SourceWhere		= '		|x|SpalteNummer = 1
												    and |x|Tarif = ''01''
												    and (
														    (|xBase|Aufnahmeleistung = 1 and cast(|xBase|Aufnahme_am   as date) between cast(|x|Wert_gueltig_von as date) and cast(|x|Wert_gueltig_bis as date)) 
													    or  (|xBase|Aufnahmeleistung = 0 and cast(|xBase|Entlassung_am as date) between cast(|x|Wert_gueltig_von as date) and cast(|x|Wert_gueltig_bis as date))
														)'
				-- Tabelle 5 - Leistung_DRG_BasisWerte
				,	@SQL_Table5_SourceName		= 'Leistung_DRG_BasisWerte'
				,	@SQL_Table1_Connect_ID5		= '|x|LastChangeOnDate'
				,	@SQL_Table5_Connect_ID		= '|x|LastChangeOnDate'
				,	@SQL_TableTargetRowID5		= '|x|RowID_BasisWerte'
				,	@SQL_Table5_SourceWhere		= 'cast(|xBase|Aufnahme_am as date) between cast(|x|Wert_gueltig_von as date) and cast(|x|Wert_gueltig_bis as date) and (|xBase|Leistung_Entgelt_Versorgungsart>0 or |xBase|Leistung_E_Statistik in (''E31'',''E33'')) and |xBase|Leistung_Entgeltsystem=''DRG'''
				-- Tabelle 6 - Leistung_Katalog_Grundwerte - für Spalten "Abteilungsart", "Versorgungsart" und "BWR"
				,	@SQL_Table6_SourceName		= 'Leistung_Katalog_Grundwerte'
				,	@SQL_Table1_Connect_ID6		= '|x|Leistung_Katalog_LeistungID'
				,	@SQL_Table6_Connect_ID		= '|x|Leistung_Katalog_LeistungID'
				,	@SQL_TableTargetRowID6		= '|x|RowID_Grundwert_BWR'
				,	@SQL_Table6_SourceWhere		= '		|xBase|Leistung_Entgelt_Versorgungsart = |x|Versorgungsart
												    and (
															(|x|Wert>0 and |x|Versorgungsart is null)
													    or   |x|Versorgungsart is not null
														)
												    and (
															(|xBase|Aufnahmeleistung = 1 and cast(|xBase|Aufnahme_am as date) between cast(|x|Wert_gueltig_von as date) and cast(|x|Wert_gueltig_bis as date))
													    or  (cast(|xBase|Entlassung_am as date) between cast(|x|Wert_gueltig_von as date) and cast(|x|Wert_gueltig_bis as date))
														)'
				-- Tabelle 7 - Leistung_Katalog_FallPauschalen
				,	@SQL_Table7_SourceName		= 'Leistung_Katalog_FallPauschalen'
				,	@SQL_Table1_Connect_ID7		= '|x|Leistung_Katalog_LeistungID'
				,	@SQL_Table7_Connect_ID		= '|x|Leistung_Katalog_LeistungID'
				,	@SQL_TableTargetRowID7		= '|x|RowID_Katalog_Fallpauschalen'
				,	@SQL_Table7_SourceWhere		= '    (|xBase|Aufnahmeleistung = 1 and cast(|xBase|Aufnahme_am as date) between cast(|x|Wert_gueltig_von as date) and cast(|x|Wert_gueltig_bis as date))
												    or (cast(|xBase|Entlassung_am as date) between cast(|x|Wert_gueltig_von as date) and cast(|x|Wert_gueltig_bis as date))'
				-- Tabelle 8 - Leistung_PEPP_Auswertung
				,	@SQL_Table8_SourceName		= 'Leistung_PEPP_Auswertung'
				,	@SQL_Table1_Connect_ID8		= '|x|LeistungID'
				,	@SQL_Table8_Connect_ID		= '|x|LeistungID'
				,	@SQL_TableTargetRowID8		= '|x|RowID_PEPP_Auswertung'
				-- Tabelle 9 - Leistung_Katalog_Bezeichnung
				,	@SQL_Table9_SourceName		= 'Leistung_Katalog_Bezeichnung'
				,	@SQL_Table1_Connect_ID9		= '|x|Leistung_Katalog_LeistungID'
				,	@SQL_Table9_Connect_ID		= '|x|Leistung_Katalog_LeistungID'
				,	@SQL_TableTargetRowID9		= '|x|RowID_Katalog_Text'
				-- Zieltabelle
				,	@SQL_TableTargetName		= 'Leistung_Pre_Basiscube'
				,	@SQL_TableTargetDefinition1 = '
						t1.LeistungID
					,	t1.FallID
					,	t1.Fallnummer
					,	t1.Leistung_Nummer
					,	t1.Leistung_Code
					,	t1.Leistung_Beginn
					,	t1.Leistung_Ende
					,	t1.Leistung_Menge
					,	t1.Leistung_Faktor
					,	t1.Leistung_Abrechnung
					,	t1.Leistung_Entgeltschluessel
					,	t1.Leistung_Entgelt_Versorgungsart
					,	t1.Leistung_E_Statistik
					,	t1.Leistung_E_Statistik_KurzText
					,	case
							when try_cast(t3.Leistung_Bewertungsformel as int)>0 then try_cast(t3.Leistung_Bewertungsformel as int)
							else 0
						end as Leistung_Bewertungsformel
					,	case
							when t3.Leistung_Bewertungsformel=4 then ''Pflegetage + Entlassungstag -> Pflegetag: Wer 23:59 Uhr im Bett liegt, kann für diesen Tag abgerechnet werden + Entlassungstag''
							when t3.Leistung_Bewertungsformel=5 then ''Leistungstage -> Entlassung – Aufnahme+1''
							when t3.Leistung_Bewertungsformel=6 then ''Berechnungstage nach BPflV 1995 -> Aufnahmetag und jeden weiteren Tag des Krankenhausaufenthalts''
							when t3.Leistung_Bewertungsformel=7 then ''Leistungstage ohne Entlassungstag -> Entlassung - Aufnahme''
							else ''Sontiges''
						end as Leistung_Bewertungsformel_KurzText
					,	t2.Behandlungstage
					,	t2.Belegungstage
					,	t2.Verweildauer
					,	t2.Aufnahme_am
					,	t2.Entlassung_am
					,	t2.AufnahmeKH
					,	t2.EntlassungKH
					,	t2.Fall_Tage_ohne_Berechnung_MD
					,	t2.Fall_Tage_ohne_Berechnung_Pflege
					,	t2.Fall_Merkmal
					,	t4.Wert as Leistung_Grundwert
					,	t5.Landesbasisfallwert
					,	t5.Pflegeentgeltwert
				
					,	case
							when t6.Abteilungsart is null and (t7.BWR_Pflege_Haupt>0 or t7.MVD_Haupt>0 or t7.Wiederaufnahme_Haupt>0 or t7.Verlegungspauschale_Haupt>0 or t7.Absenkung_Haupt>0) then ''Hauptabteilung''
							when t6.Abteilungsart is null then ''Sonstige''
							else t6.Abteilungsart 
						end as Abteilungsart
					,	isnull(t6.Versorgungsart,0) as Versorgungsart
					,	t6.Wert AS BWR
				
					,	Case when t6.Abteilungsart=''Hauptabteilung'' or (t6.Abteilungsart is null and t7.MVD_Haupt>0) then isnull(t7.MVD_Haupt,0) else isnull(t7.MVD_Beleg,0) end as MVD
					,	Case when t6.Abteilungsart=''Hauptabteilung'' or (t6.Abteilungsart is null and t7.OGVD_Haupt>0) then isnull(t7.OGVD_Haupt,0) else isnull(t7.OGVD_Beleg,0) end as OGVD
					,	Case when t6.Abteilungsart=''Hauptabteilung'' or (t6.Abteilungsart is null and t7.UGVD_Haupt>0) then isnull(t7.UGVD_Haupt,0) else isnull(t7.UGVD_Beleg,0) end as UGVD
					,	Case when t6.Abteilungsart=''Hauptabteilung'' or (t6.Abteilungsart is null and t7.BWR_UGVD_Haupt>0) then isnull(t7.BWR_UGVD_Haupt,0) else isnull(t7.BWR_UGVD_Beleg,0) end as BWR_UGVD
					,	Case when t6.Abteilungsart=''Hauptabteilung'' or (t6.Abteilungsart is null and t7.BWR_OGVD_Haupt>0) then isnull(t7.BWR_OGVD_Haupt,0) else isnull(t7.BWR_OGVD_Beleg,0) end as BWR_OGVD
					,	Case when t6.Abteilungsart=''Hauptabteilung'' or (t6.Abteilungsart is null and t7.BWR_Pflege_Haupt>0) then isnull(t7.BWR_Pflege_Haupt,0) else isnull(t7.BWR_Pflege_Beleg,0) end as BWR_Pflege
					,	Case when t6.Abteilungsart=''Hauptabteilung'' or (t6.Abteilungsart is null and t7.BWR_Verlegung_Haupt>0) then isnull(t7.BWR_Verlegung_Haupt,0) else isnull(t7.BWR_Verlegung_Beleg,0) end as BWR_Verlegung
					,	Case when t6.Abteilungsart=''Hauptabteilung'' or (t6.Abteilungsart is null and t7.Wiederaufnahme_Haupt>0) then isnull(t7.Wiederaufnahme_Haupt,0) else isnull(t7.Wiederaufnahme_Beleg,0) end as Wiederaufnahme
					,	Case when t6.Abteilungsart=''Hauptabteilung'' or (t6.Abteilungsart is null and t7.Verlegungspauschale_Haupt>0) then isnull(t7.Verlegungspauschale_Haupt,0) else isnull(t7.Verlegungspauschale_Beleg,0) end as Verlegungspauschale
				
					,	t8.PEPP_Bezugsgroesse
					,	t8.PEPP_Stufe
					,	t8.Rang as PEPP_Rang
					,	t8.PEPP_RelGew
					,	t8.PEPP_Betrag
					,	t8.PEPP_BWR
				
					,	t9.Leistung_Katalog_KurzText
				';

			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1, @LogStepSQL2=@SQL2, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 

Post50:
			SET @SQL=''; SET @SQL1=''; SET @SQL2=''; SET @SQL3=''
			SET @StepPraefix	= 'Post50'
			SET @StepText		= 'Tabelle [Leistung_Basiscube] aus Tabelle [Leistung_Pre_Basiscube] erstellen.'

			SET @SQL=CONCAT('
				DROP TABLE IF EXISTS ', @SQL_TableTargetDB, '.',@SQL_TableTargetSchema, '.Leistung_Basiscube;

				SELECT
					RowID
				,	SchluesselID
				,	LeistungID
				,	FallID
				,	Fallnummer
				,	Leistung_Nummer
				,	Leistung_Code
				,	Leistung_Katalog_KurzText
				,	Leistung_Beginn
				,	Leistung_Ende
				,	Leistung_Menge
				,	Leistung_Faktor
				,	Leistung_Entgeltschluessel
				,	Leistung_Entgelt_Versorgungsart
				,	Leistung_E_Statistik
				,	Leistung_E_Statistik_KurzText
				,	Leistung_Bewertungsformel
				,	Leistung_Bewertungsformel_KurzText
				,	Behandlungstage
				,	Belegungstage
				,	Verweildauer
				,	Aufnahme_am
				,	Entlassung_am
				,	AufnahmeKH
				,	EntlassungKH
				,	Fall_Tage_ohne_Berechnung_MD
				,	Fall_Tage_ohne_Berechnung_Pflege
				,	Leistung_Grundwert
				,	Landesbasisfallwert
				,	Pflegeentgeltwert
				,	PEPP_Bezugsgroesse
				,	PEPP_Stufe
				,	PEPP_Rang
				,	Abteilungsart
				,	MVD
				,	OGVD
				,	UGVD
				,	BWR_UGVD
				,	BWR_OGVD
				,	BWR_Pflege
				,	BWR_Verlegung
				,	Wiederaufnahme
				,	Verlegungspauschale
				,	case when Versorgungsart = 0 then PEPP_RelGew else isnull(PEPP_RelGew,BWR) end as Relativgewicht')
			SET @SQL1 = '
				,	isnull(
						PEPP_Betrag
					,	case
							when Leistung_E_Statistik = ''E33'' and Leistung_Bewertungsformel <> 7
							then Leistung_Grundwert * Verweildauer
							else
								case
									when Leistung_E_Statistik = ''E33'' and Leistung_Bewertungsformel = 7
									then Leistung_Grundwert * Behandlungstage
									else
										case
											when Leistung_E_Statistik in (''E2'',''E32'',''NUB'')
											then Leistung_Grundwert * Leistung_Menge
											else
												isnull(
													Landesbasisfallwert * (BWR + case
																					when ((Verlegungspauschale = 1 and Verweildauer < UGVD) or ((Verlegungspauschale = 1 or (AufnahmeKH = 0 and EntlassungKH = 0)) and Verweildauer <= UGVD)) and (isnull(Fall_Merkmal, '''') <> ''Kinder2023'')
																					then (UGVD - Verweildauer + 1) * -BWR_UGVD
																					else 0
																				 end
																			   + case
																					when Verweildauer >= OGVD
																					then (Verweildauer - OGVD + 1) * BWR_OGVD
																					else 0
																				 end
																			   + case
																					when Verlegungspauschale = 0 and ((EntlassungKH = 1) or (AufnahmeKH = 1)) and Verweildauer < Round(MVD, 0)
																					then (Round(MVD, 0) - Verweildauer) * -BWR_Verlegung
																					else 0
																				 end
																		  )
												,	0
												)
										end
								end
						end
					) as Gesamtbetrag
				,	isnull(
						PEPP_BWR
					,	case
							when Leistung_E_Statistik = ''E33'' and Leistung_Bewertungsformel <> 7
							then Leistung_Grundwert * Verweildauer
							else
								case
									when Leistung_E_Statistik = ''E33'' and Leistung_Bewertungsformel = 7
									then Leistung_Grundwert * Behandlungstage
									else
										case
											when Leistung_E_Statistik in (''E2'',''E32'',''NUB'')
											then Leistung_Grundwert * Leistung_Menge
											else
												isnull(
													Landesbasisfallwert * (BWR + case
																					when ((Verlegungspauschale = 1 and Verweildauer < UGVD) or ((Verlegungspauschale = 1 or (AufnahmeKH = 0 and EntlassungKH = 0)) and Verweildauer <= UGVD)) and (isnull(Fall_Merkmal, '''') <> ''Kinder2023'')
																					then (UGVD - Verweildauer + 1) * -BWR_UGVD
																					else 0
																				 end
																			   + case
																					when Verweildauer >= OGVD
																					then (Verweildauer - OGVD + 1) * BWR_OGVD
																					else 0
																				 end
																			   + case
																					when Verlegungspauschale = 0 and ((EntlassungKH = 1) or (AufnahmeKH = 1)) and Verweildauer < Round(MVD, 0)
																					then (Round(MVD, 0) - Verweildauer) * -BWR_Verlegung
																					else 0
																				 end
																		  )
												,	0
												)
										end
								end
						end / Landesbasisfallwert
					) as Effektivgewicht'
			SET @SQL2 = '
				,	case when BWR_Pflege > 0 then (Verweildauer + Fall_Tage_ohne_Berechnung_MD - Fall_Tage_ohne_Berechnung_Pflege) * BWR_Pflege * Pflegeentgeltwert else Null end as DRG_PflegeEntgelt
				,	case when BWR_Pflege > 0 then (Verweildauer + Fall_Tage_ohne_Berechnung_MD - Fall_Tage_ohne_Berechnung_Pflege) * BWR_Pflege else Null end as DRG_Pflege_RelGew
				,	case
						when Verweildauer >= OGVD then ''Langlieger''
						when Verweildauer <= UGVD then ''Kurzlieger''
						when Verweildauer >  UGVD and Verweildauer < OGVD then ''Normallieger''
						else Null
					end as DRG_Liegestatus
				,	case
						when Verweildauer >= MVD and Verweildauer < OGVD then ''Costlier''
						when Verweildauer <  MVD and Verweildauer > UGVD then ''Profitlier''
						else Null
					end as DRG_Liegestatus_Wert
				,	case
						when Verweildauer < OGVD
						and not(((AufnahmeKH = 1 and Verlegungspauschale = 0) or Verlegungspauschale = 1 or (AufnahmeKH = 0 and EntlassungKH = 0)) and Verweildauer <= UGVD)
						and not(Verlegungspauschale = 0 and ((EntlassungKH = 1) or (AufnahmeKH = 1 and Verweildauer >= UGVD)) and Verweildauer < Round(MVD, 0))
						then 1
						else 0
					end as DRG_Normallieger
				,	case
						when Verweildauer < OGVD
						and not(((AufnahmeKH = 1 and Verlegungspauschale = 0) or Verlegungspauschale = 1 or (AufnahmeKH = 0 and EntlassungKH = 0)) and Verweildauer <= UGVD)
						and not(Verlegungspauschale = 0 and ((EntlassungKH = 1) or (AufnahmeKH = 1 and Verweildauer >= UGVD)) and Verweildauer < Round(MVD, 0))
						then BWR
						else Null
					end as DRG_Normallieger_RelGew
				,	case
						when Verweildauer < OGVD
						and not(((AufnahmeKH = 1 and Verlegungspauschale = 0) or Verlegungspauschale = 1 or (AufnahmeKH = 0 and EntlassungKH = 0)) and Verweildauer <= UGVD)
						and not(Verlegungspauschale = 0 and ((EntlassungKH = 1) or (AufnahmeKH = 1 and Verweildauer >= UGVD)) and Verweildauer < Round(MVD, 0))
						then Verweildauer
						else 0
					end as DRG_Normallieger_Tage'
			SET @SQL3 = CONCAT('
				,	case when Verweildauer >= OGVD then 1 else 0 end as DRG_Langlieger
				,	case when Verweildauer >= OGVD then (Verweildauer - OGVD + 1) * BWR_OGVD else Null end as DRG_Langlieger_RelGew
				,	case when Verweildauer >= OGVD then (Verweildauer - OGVD + 1) else 0 end as DRG_Langlieger_Tage
				,	case when (Verlegungspauschale = 1 or (AufnahmeKH = 0 and EntlassungKH = 0)) and Verweildauer <= UGVD and (isnull(Fall_Merkmal,'''') <> ''Kinder2023'') then 1 else 0 end as DRG_Kurzlieger
				,	case when (Verlegungspauschale = 1 or (AufnahmeKH = 0 and EntlassungKH = 0)) and Verweildauer <= UGVD and (isnull(Fall_Merkmal,'''') <> ''Kinder2023'') then (UGVD - Verweildauer + 1) * -BWR_UGVD else Null end as DRG_Kurzlieger_RelGew
				,	case when (Verlegungspauschale = 1 or (AufnahmeKH = 0 and EntlassungKH = 0)) and Verweildauer <= UGVD and (isnull(Fall_Merkmal,'''') <> ''Kinder2023'') then (UGVD - Verweildauer + 1) else 0 end as DRG_Kurzlieger_Tage
				,	case when Verlegungspauschale = 0 and (EntlassungKH = 1) and Verweildauer < Round(MVD, 0) then 1 else 0 end as DRG_EntlassVerlegung
				,	case when Verlegungspauschale = 0 and (AufnahmeKH = 1)	and Verweildauer < Round(MVD, 0) then 1 else 0 end as DRG_AufnahmeVerlegung
				,	case when Verlegungspauschale = 0 and ((EntlassungKH = 1) or (AufnahmeKH = 1)) and Verweildauer < Round(MVD, 0) then (Round(MVD, 0) - Verweildauer) else 0 end as DRG_Verlegung_Tage
				,	case when Verlegungspauschale = 0 and ((EntlassungKH = 1) or (AufnahmeKH = 1)) and Verweildauer < Round(MVD, 0) then (Round(MVD, 0) - Verweildauer) * -BWR_Verlegung else 0 end	as DRG_Verlegung_RelGew
				,	Aufnahmeleistung AS Leistung_Aufnahme
				,	Leistung_Abrechnung
				,	Fall_Merkmal
				,	Aufnahmeleistung
				,	Leistung_Entgeltsystem
				,	Leistung_Katalog_LeistungID
				,	RowID_BasisWerte
				,	RowID_Grundwert
				,	RowID_Grundwert_BWR
				,	RowID_Katalog_Eigenschaften
				,	RowID_Katalog_Fallpauschalen
				,	RowID_Leistung
				,	RowID_PEPP_Auswertung
				,	RowID_Verweildauer
				,	RowID_Katalog_Text
				,	Rang
				,	HashID
				,	Hash_Bereich
				,	Datensatz_gueltig_von
				,	Datensatz_gueltig_bis
				,	LastChangeOnDate
				,	LastChange

				INTO ', @SQL_TableTargetDB, '.',@SQL_TableTargetSchema, '.Leistung_Basiscube

				FROM ', @SQL_TableTargetDB, '.',@SQL_TableTargetSchema, '.Leistung_Pre_Basiscube

			')

			EXEC(@SQL+@SQL1+@SQL2+@SQL3);
			SELECT @Fehler = @@ERROR, @RowCount = @@ROWCOUNT
			EXEC dbo.Logging @LogID=@LogID, @LogStep=@StepPraefix, @LogStepText=@StepText, @LogStepSQL=@SQL,@LogStepSQL1=@SQL1,@LogStepSQL2=@SQL2,@LogStepSQL3=@SQL3, @LogStepRows=@RowCount, @LogTableProcessMode='PostProcessing', @LogStepError=@Fehler 


		end

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



