USE Analysen
GO
--exec UpdateBaseTable_ISH_Organisation @Ladeverfahren='D',@TEMPPraefix=294025922, @PreProcessing=0, @MainProcessing=0, @PostProcessing=1
--Select * from dbo.UpdateBaseTable_ISH_Organisation
CREATE OR ALTER PROC dbo.UpdateBaseTable_ISH_Organisation

	@DELAY int						=60,	--> Greift im Fasttrack auch die Daten n-Tage vor dem letzten Ladevorgang ab. 
	@MaxDelay	as int				=0,		--> Maximale Verzögerung des letzten Aktualisierung einer Quelltabelle in Minuten. Insofern 0 oder negative Zahlen verwendet werden, bezieht sich die Verzögerung auf Tage. (0 die Aktualisierung muss von heute sein, -1 die Aktualisierung muss von gestern sein)
	@DaysToFullLoad int						=7,		--> Aller wieviel Tage soll ein Fullload durchgeführt werden?
	@TestLoop nvarchar(100)	='',	--> bspw. 'Top 100' für 100 Testdatensätze
	@DeltaDays as int					=1,		--> Delta-Load beinhaltet n volle Tage 
	@FullloadYears as int				=10,	--> Jahre die als Fullload geladen werden sollen, 0=Delta-Load
	@Ladeverfahren as nvarchar(2)	='F',	--> Wenn 'F' dann Fulload, wenn 'D' dann Deltaload, Sonst entscheidet das Skript automatische über das Ladeverfahren anhand der Einstellungen
	@CDPOS_laden as int				=1,		--> Wenn 1 wird CDPOS geladen, wenn 0 wird CDPOS nicht geladen
	@LastChangeFromTarget as int	=1,		--> Wenn 1 wird der letzte Änderungszeitpunkt aus der TargetTabelle berechnet - langsam/0=Änderungszeitpunkt wird aus den SYS-Tabellen berechnet
	@HashAbgleich_ct as int			=1,		--> 1=Nur relevanten Änderungen in den ct Tabellen werden mit einem HASH über die ausgewählten Spalten verarbeitet/0=keine Hash-Prüfung im ersten Schritt
	@Historisierung as int			=1,		--> 1=Historisierte Werte aus CT-Tabellen und der CDPOS werden abgefragt / 0=keine historisierten Werte
	@PreProcessing as int			=1,		--> 1=Vorprozesse werden ausgeführt
	@MainProcessing as int			=1,		--> 1=Hauptprozesse werden ausgeführt
	@PostProcessing as int			=1,		--> 1=Nachprozesse werden ausgeführt
	@TEMPPraefix as nvarchar(100)	='New',	--> 'New' wird eine neue TempID für alle Temptabellen vergeben
	@TEMPLoeschen as int			=1,		--> 1=Tempdateien werden gelöscht
	@StartStep as varchar(10)		='',	--> Startet mit Prozessschritt bspw. 'XP270'
	@ValidToStorno as int			=1,		--> Wenn 1 wird der Gültigkeitszeitraum des Datensatzes zum Stornozeitpunkt beendet (Standard). Wenn 0 ist der Datensatz auch nach dem Stornozeitpunkt gültig.
	@ValidBeforeStorno as int		=1,		--> Wenn 1 sind alle Datensätze eine Zeiteinheit vor einem Storno gültig (Standard). Wenn 0 sind alle Datensätze genau bis zum Storno gültig.

	@SQL_TableTargetDB as nvarchar(200)		='Analysen',	--> Datenbankname für die Zieltabelle
	@SQL_TableTargetSchema as nvarchar(200)	='dbo'			--> Schemaname in der Datenbank für die Zieltabelle

as
Begin

	PRINT 'Starte Skripabarbeitung für Prozedur [UpdateBaseTable_ISH_Organisation]'

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
	DECLARE @SQL_TableTargetID as nvarchar(500)
	DECLARE @SQL_TableTarget_Join as nvarchar(max)
	DECLARE @SQL_TableTargetDefinition1 as nvarchar(max)
	DECLARE @SQL_TableTargetDefinition2 as nvarchar(max)
	DECLARE @CDPOS_TableID as nvarchar(200)

	DECLARE @SQL as nvarchar(max)
	DECLARE @SQL1 as nvarchar(max)
	DECLARE @SQL2 as nvarchar(max)

	SET @SQL_TableSourceDB			= 'replicate'
	SET @SQL_TableSourceSchema		= 'sap'

	if @PreProcessing=1
		Begin

			--TN10S: OrganisationISH_Typ_Text
			--Select * from replicate.sap.TN10S
			--Select * from OrganisationISH_Typ_Text
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@CDPOS_laden=0,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='TN10S',
					@SQL_TableSourceFields='ORGTY,OTTXT',
					@SQL_TableSourceID='concat(|x|MANDT,|x|EINRI,|x|ORGTY)',
					@SQL_TableSourceCreateDate=	'cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceUpDate=		'cast(''1.1.1990 00:00:00'' as datetime)',
					@SQL_TableSourceStornoDate=	'cast(''31.12.2099 23:59:59'' as datetime)', @SQL_TableSourceStornoFlag='0', 					
					@ValidToStorno	= 1, @ValidBeforeStorno=0,
					@SQL_TableSource_Where='|x|SPRAS=''D''',
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='OrganisationISH_Typ_Text',
					@SQL_TableTargetID='|x|OrganisationISH_TypID',
					@SQL_TableTargetDefinition1='|x|OTTXT as KurzText',
					@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen

			--TN10B: OrganisationISH_Bettenzahl
			--Select * from replicate.sap.TN10B
			--Select * from OrganisationISH_Bettenzahl
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@CDPOS_laden=0,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='TN10B',
					@SQL_TableSourceFields='MANDT,ORGFA,ORGPF,PBSUM,PBKHG,PBHBFG,PBSON,ABSUM,ABKHG,ABHBFG,ABVER,ABSON,ABINT,ABBELEG,PBVIP,PBNEGA,PBRES,ABVIP,ABNEGA,ABRES',
					@SQL_TableSourceID='concat(|x|MANDT,|x|ORGFA,|x|ORGPF)',
					@SQL_TableSourceCreateDate=	'isnull(try_cast(|x|RI_BEGDT as datetime),cast(''1.1.1990 00:00:00'' as datetime))',
					@SQL_TableSourceUpDate=		'isnull(try_cast(|x|RI_BEGDT as datetime),cast(''1.1.1990 00:00:00'' as datetime))',
					@SQL_TableSourceStornoDate=	'isnull(try_cast(|x|RI_ENDDT as datetime)+cast(''23:59:59'' as datetime), cast(''31.12.2099 23:59:59'' as datetime))', @SQL_TableSourceStornoFlag='0', 
					@ValidToStorno	= 1, @ValidBeforeStorno=0,
					@SQL_TableSource_Where='',
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='OrganisationISH_Bettenzahl',
					@SQL_TableTargetID='|x|OrganisationISH_FachPflegeID',
					@SQL_TableTargetDefinition1='cast(|x|PBSUM as int) as PBSUM,
					cast(|x|PBKHG as int) as PBKHG,
					cast(|x|PBHBFG as int) as PBHBFG,
					cast(|x|PBSON as int) as PBSON,
					cast(|x|ABSUM as int) as ABSUM,
					cast(|x|ABKHG as int) as ABKHG,
					cast(|x|ABHBFG as int) as ABHBFG,
					cast(|x|ABVER as int) as ABVER,
					cast(|x|ABSON as int) asABSON,
					cast(|x|ABINT as int) as ABINT,
					cast(|x|ABBELEG as int) as ABBELEG,
					cast(|x|PBVIP as int) as PBVIP,
					cast(|x|PBNEGA as int) as PBNEGA,
					cast(|x|PBRES as int) as PBRES,
					cast(|x|ABVIP as int) as ABVIP,
					cast(|x|ABNEGA as int) as ABNEGA,
					cast(|x|ABRES as int) as ABRES',
					@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen

			--TN10H: OrganisationISH_Hierarchie
			--Select * from replicate.sap.TN10H where untor='CH1-5'
			--Select * from OrganisationISH_Hierarchie
	
			--DECLARE @TEMPPraefix as nvarchar(100);DECLARE @TEMPLoeschen as int;DECLARE @SQL_TableSourceDB as nvarchar(200);DECLARE @SQL_TableSourceSchema as nvarchar(200);DECLARE @SQL_TableTargetDB as nvarchar(200);DECLARE @SQL_TableTargetSchema as nvarchar(200);DECLARE @DELAY as int; DECLARE @DaysToFullLoad as int; DECLARE @DeltaDays as int; DECLARE @FullloadYears as int; DECLARE @Ladeverfahren as nvarchar(2); DECLARE @CDPOS_laden as int; DECLARE @LastChangeFromTarget as int; DECLARE @HashAbgleich_ct as int; DECLARE @Historisierung as int;	Set @SQL_TableSourceDB='Replicate';Set @SQL_TableSourceSchema='sap';Set @SQL_TableTargetDB='Analysen';Set @SQL_TableTargetSchema='dbo';Set @TEMPLoeschen=0; Set @TEMPLoeschen=62944979; SET @DELAY=10; SET @DaysToFullLoad=7; SET @DeltaDays=1; SET @FullloadYears=5; SET @Ladeverfahren='FN'; SET @CDPOS_laden=0; SET @LastChangeFromTarget=1; SET @HashAbgleich_ct=1; SET @Historisierung=1 
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@CDPOS_laden=0,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='TN10H',
					@SQL_TableSourceFields='MANDT,UEBOR,UNTOR',
					@SQL_TableSourceID='concat(|x|MANDT,|x|UNTOR)',
					@SQL_TableSourceCreateDate='case when try_cast(|x|BEGDT as datetime)>0 then cast(|x|BEGDT as datetime) else Null end',
					@SQL_TableSourceUpDate='case when try_cast(|x|UPDAT as datetime)>0 then cast(|x|UPDAT as datetime) else Null end',
					@SQL_TableSourceStornoDate='case when year(|x|ENDDT)>2099 then cast(''31.12.2099 23:59:59'' as datetime) else cast(|x|ENDDT as datetime) + cast(''23:59:59'' as datetime) end',
					@SQL_TableSourceStornoFlag='case when year(|x|ENDDT)>2099 then 0 else 1 end',	
					@ValidToStorno	= 1, @ValidBeforeStorno=0,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='OrganisationISH_Hierarchie',
					@SQL_TableTargetID='|x|OrgID',
					@SQL_TableTargetDefinition1='
					concat(|x|MANDT,|x|UEBOR) as Parent_OrgID
					,|x|UEBOR as Kuerzel_Parent
					,|x|UNTOR as Kuerzel',
					@SQL_TableTarget_Where='t1.LastChangeOnDate=1',
					@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen

			--NORG: OrganisationISH_Aenderungshistorie
			--Select * from replicate.sap.NORG
			--Select * from OrganisationISH_Aenderungshistorie

			--DECLARE @TEMPPraefix as nvarchar(100);DECLARE @TEMPLoeschen as int;DECLARE @SQL_TableSourceDB as nvarchar(200);DECLARE @SQL_TableSourceSchema as nvarchar(200);DECLARE @SQL_TableTargetDB as nvarchar(200);DECLARE @SQL_TableTargetSchema as nvarchar(200);DECLARE @DELAY as int; DECLARE @DaysToFullLoad as int; DECLARE @DeltaDays as int; DECLARE @FullloadYears as int; DECLARE @Ladeverfahren as nvarchar(2); DECLARE @CDPOS_laden as int; DECLARE @LastChangeFromTarget as int; DECLARE @HashAbgleich_ct as int; DECLARE @Historisierung as int;	Set @SQL_TableSourceDB='Replicate';Set @SQL_TableSourceSchema='sap';Set @SQL_TableTargetDB='Analysen';Set @SQL_TableTargetSchema='dbo';Set @TEMPLoeschen=0; Set @TEMPLoeschen=62944979; SET @DELAY=10; SET @DaysToFullLoad=7; SET @DeltaDays=1; SET @FullloadYears=5; SET @Ladeverfahren='FN'; SET @CDPOS_laden=0; SET @LastChangeFromTarget=1; SET @HashAbgleich_ct=1; SET @Historisierung=1 
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@CDPOS_laden=1,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='NORG',
					@SQL_TableSourceFields='MANDT,EINRI,ORGID,ORGTY,ORGNA,ORGZU,ORGKB,OKURZ,BELEG,FAZUW,PFZUW,AUFKZ,INTKZ,AMBES,FACHR,FACHR1,FACHR2,FACHR3,SPERR',
					@SQL_TableSourceID='CONCAT(|x|MANDT,|x|EINRI,|x|ORGID)',
					@SQL_TableSourceCreateDate='case when year(|x|ERDAT)=101 then 
													try_cast(|x|BEGDT as datetime) + cast(''00:00:00'' as datetime) 
											   else try_cast(|x|ERDAT as datetime) + cast(''00:00:00'' as datetime) end',
					@SQL_TableSourceUpDate='case when year(try_cast(|x|UPDAT as datetime))>1970 then 
													try_cast(|x|UPDAT as datetime) + cast(''23:59:59'' as datetime) 
											   else case when year(|x|ERDAT)=101 then 
														try_cast(|x|BEGDT as datetime) + cast(''23:59:59'' as datetime) 
													else try_cast(|x|ERDAT as datetime) + cast(''23:59:59'' as datetime) end end',
					@SQL_TableSourceStornoDate='case when |x|LOEKZ=''X'' then try_cast(|x|LODAT as datetime) else try_cast(''31.12.2099 23:59:59'' as datetime) end ', 
					@SQL_TableSourceStornoFlag='case when |x|LOEKZ=''X'' then 1 else 0 end', 
					@SQL_TableSourceStornoField = '|x|LOEKZ',	
					@ValidToStorno	= 1, @ValidBeforeStorno=1,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='OrganisationISH_Aenderungshistorie',
					@SQL_TableTargetID='|x|OrganisationISH_ID',
					@SQL_TableTargetDefinition1=	
					'concat(MANDT, ORGID) as OrgID
					,concat(MANDT, EINRI, ORGTY) as TypID
					,ORGID as Kuerzel
					,ORGTY as Typ
					,ORGNA as Name
					,ORGZU as Zugehoerigkeit
					,ORGKB as Klinikbereich
					,OKURZ as Kuerzel5
					,case when BELEG = ''X'' then 1 else 0 end as Belegabteilung
					,case when FAZUW = ''X'' then 1 else 0 end as Fachabteilung
					,case when PFZUW = ''X'' then 1 else 0 end as Pflegebereich
					,case when INTKZ = ''X'' then 1 else 0 end as Intensiv
					,case when AMBES = ''X'' then 1 else 0 end as Ambulant
					,FACHR  as Fachrichtung
					,FACHR1 as Fachrichtung1
					,FACHR2 as Fachrichtung2
					,FACHR3 as Fachrichtung3
					,case when SPERR = ''X'' then 1 else 0 end as ist_gesperrt',
					@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen, @CDPOS_TableID	= 'CONCAT(|x|MANDANT,|x|OBJECTID)'
	
			--NOEK: OrganisationISH_Kostenstelle
			--Select * from replicate.sap.NOEK
			--Select * from OrganisationISH_Kostenstelle
			Execute dbo.UpdateBaseTable_Aenderungshistorie
					@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@CDPOS_laden=0,
					@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
					@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
					@SQL_TableSourceName='NOEK',
					@SQL_TableSourceFields='MANDT,ORGFA,ORGPF,KOSTL',
					@SQL_TableSourceID='concat(|x|MANDT,|x|ORGFA,|x|ORGPF)',
					@SQL_TableSourceCreateDate='case when try_cast(|x|BEGDT as datetime)>0 then cast(|x|BEGDT as datetime) else Null end',
					@SQL_TableSourceUpDate='case when try_cast(|x|UPDAT as datetime)>0 then cast(|x|UPDAT as datetime) else try_cast(|x|BEGDT as datetime) end',
					@SQL_TableSourceStornoDate='case when year(|x|ENDDT)>2099 then cast(''31.12.2099 23:59:59'' as datetime) else cast(|x|ENDDT as datetime) + cast(''23:59:59'' as datetime) end',
					@SQL_TableSourceStornoFlag='case when year(|x|ENDDT)>2099 then 0 else 1 end',	
					@ValidToStorno	= 1, @ValidBeforeStorno=0,
					@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
					@SQL_TableTargetName='OrganisationISH_Kostenstelle',
					@SQL_TableTargetID='|x|OrganisationISH_FachPflegeID',
					@SQL_TableTargetDefinition1='
					 |x|ORGPF as OrganisationISH_Pflege
					,|x|ORGFA as OrganisationISH_Fach
					,|x|KOSTL as Kostenstelle
					,try_cast(|x|KOSTL as bigint) as Kostenstelle_Zahlenwert',
					@SQL_TableTarget_Where='t1.LastChangeOnDate=1',
					@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen

		End

	if @MainProcessing=1
		Begin

			Print 'MainProcessing'
			--OrganisationISH_HierarchieBaum
			--Select * from OrganisationISH_HierarchieBaum
			--Select * from OrganisationISH_Hierarchie
			--Declare @SQL_TableTargetDB as nvarchar(200); Declare @SQL_TableTargetSchema as nvarchar(200); Declare @SQL as nvarchar(max); Declare @SQL1 as nvarchar(max); Declare @SQL2 as nvarchar(max); Set @SQL_TableTargetDB='Analysen'; Set @SQL_TableTargetSchema='dbo'
			Set @SQL=''; Set @SQL1=''; Set @SQL2=''

			Set @SQL=CONCAT('
			Drop table if exists ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.OrganisationISH_HierarchieBaum;

			With Baum
			AS
			(
				SELECT  distinct 
					t1.OrgID
					,cast(Null as nvarchar(11)) as Parent_OrgID
					,1 As Org_Ebene
					,cast(t1.OrgID AS VARCHAR(MAX)) as Org_Pfad
					,t1.OrgID as ORG_Wurzel
					,t1.Datensatz_gueltig_von
					,t1.Datensatz_gueltig_bis
				FROM ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.OrganisationISH_Aenderungshistorie t1
					left Join (Select Distinct OrgID, Datensatz_gueltig_von, Datensatz_gueltig_bis 
								from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.OrganisationISH_Hierarchie) t2 on t1.OrgID=t2.OrgID 
									and (t1.Datensatz_gueltig_von between t2.Datensatz_gueltig_von and t2.Datensatz_gueltig_bis
									or t1.Datensatz_gueltig_bis between t2.Datensatz_gueltig_von and t2.Datensatz_gueltig_bis
									or (t1.Datensatz_gueltig_von < t2.Datensatz_gueltig_von and t1.Datensatz_gueltig_bis>t2.Datensatz_gueltig_bis))
					where t2.OrgID is null and t1.LastChangeOnDate=1

				UNION ALL')
			Set @SQL1=CONCAT('
				Select 		 
					t1.OrgID
					,t1.Parent_OrgID
					,cast(B.Org_Ebene as int) + 1 as Org_Ebene
					,CAST((B.Org_Pfad + ''|'' + t1.OrgID) AS VARCHAR(MAX)) as Org_Pfad
					,B.ORG_Wurzel
					,t1.Datensatz_gueltig_von
					,t1.Datensatz_gueltig_bis
				from ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.OrganisationISH_Hierarchie t1
					join Baum AS B ON t1.Parent_OrgID = B.OrgID and (B.Datensatz_gueltig_von between t1.Datensatz_gueltig_von and t1.Datensatz_gueltig_bis
																		or B.Datensatz_gueltig_bis between t1.Datensatz_gueltig_von and t1.Datensatz_gueltig_bis
																		or (B.Datensatz_gueltig_von < t1.Datensatz_gueltig_von and B.Datensatz_gueltig_bis>t1.Datensatz_gueltig_bis))
				where t1.Parent_OrgID is not null 
			),
			Pivottabelle
			as (
				Select * from ')
			Set @SQL2=CONCAT('
					(
					Select 
						t1.OrgID
						,t1.Parent_OrgID
						,t1.Org_Pfad
						,t1.ORG_Wurzel
						,t1.Org_Ebene
						,max(Org_Ebene) OVER(PARTITION BY t1.OrgID) as maxebene
						,''Org_Ebene''+ CAST(ROW_NUMBER()OVER(PARTITION BY t1.OrgID, t1.Org_Pfad, t1.Datensatz_gueltig_von ORDER BY t1.Org_Pfad) AS VARCHAR) AS Col1
						,Split.value as Split_Wert
						,t1.Datensatz_gueltig_von
						,t1.Datensatz_gueltig_bis
					from Baum t1
							CROSS APPLY String_split(Org_Pfad,''|'') AS Split
					) as t1
						Pivot (min(Split_Wert) FOR Col1 IN (Org_Ebene1,Org_Ebene2,Org_Ebene3,Org_Ebene4,Org_Ebene5,Org_Ebene6)) AS t2
				)

			Select OrgID, Parent_OrgID, Org_Pfad, ORG_Wurzel, Org_Ebene, Org_Ebene1,Org_Ebene2,Org_Ebene3,Org_Ebene4,Org_Ebene5,Org_Ebene6
					,Rank() over (partition by OrgID order by Datensatz_gueltig_von DESC) as Rang
					,Datensatz_gueltig_von
					,Datensatz_gueltig_bis
			into ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.OrganisationISH_HierarchieBaum
			from Pivottabelle');

			Print (@SQL+@SQL1+@SQL2)
			Exec (@SQL+@SQL1+@SQL2)

		End

	if @PostProcessing=1
		Begin

			--JOIN: OrganisationISH_BasisCube
			--Select * from OrganisationISH_BasisCube
			SET	@SQL_TableTarget_Join = Concat('',' 
			left join ',@SQL_TableTargetDB,'.',@SQL_TableTargetSchema,'.OrganisationISH_HierarchieBaum tBaum on t3.OrgID=tBaum.OrgID and (t3.Parent_OrgID=tBaum.Parent_OrgID or t3.Parent_OrgID is null)')

			Execute [dbo].[TabJoin]
				@TEMPLoeschen=@TEMPLoeschen, @TEMPPraefix=@TEMPPraefix, @SQL_TableTargetDB	=@SQL_TableTargetDB, @SQL_TableTargetSchema =@SQL_TableTargetSchema,@MaxDelay=@MaxDelay, @Ladeverfahren=@Ladeverfahren,	
				@SQL_Table1_SourceName ='OrganisationISH_Aenderungshistorie',	 @SQL_Table1_ID ='|x|OrganisationISH_ID',
				@SQL_Table2_SourceName ='OrganisationISH_Typ_Text',		@SQL_Table1_Connect_ID2 ='|x|TypID',				@SQL_Table2_Connect_ID ='|x|OrganisationISH_TypID',		@SQL_TableTargetRowID2 ='|x|RowID_TypText',
				@SQL_Table3_SourceName ='OrganisationISH_Hierarchie',	@SQL_Table1_Connect_ID3 ='|x|OrgID',				@SQL_Table3_Connect_ID ='|x|OrgID',						@SQL_TableTargetRowID3 ='|x|RowID_Hierarchie',	
				@SQL_TableTargetName   ='OrganisationISH_BasisCube', 
				@SQL_TableTargetJoin=@SQL_TableTarget_Join,
				@SQL_TableTargetDefinition1='
				t1.OrganisationISH_ID
				,t1.OrgID
				,t3.Parent_OrgID
				,tBaum.Org_Pfad as Pfad
				,tBaum.Org_Wurzel as Pfad_Wurzel
				,tBaum.Org_Ebene as Pfad_Tiefe
				,tBaum.Org_Ebene1 as Pfad_Ebene1
				,tBaum.Org_Ebene2 as Pfad_Ebene2
				,tBaum.Org_Ebene3 as Pfad_Ebene3
				,tBaum.Org_Ebene4 as Pfad_Ebene4
				,tBaum.Org_Ebene5 as Pfad_Ebene5
				,tBaum.Org_Ebene6 as Pfad_Ebene6
				,t1.Typ as Typ_Original
				,case when len(t1.Kuerzel)>6 then 
					case substring(t1.Kuerzel,6,1)
						when ''N'' then 
							case when right(t1.Kuerzel,3)=''NOT'' then ''(NO) Notfall'' else ''(NO) Notfall ('' + right(t1.Kuerzel,2) + '')'' end
						when ''A'' then 
							case when right(t1.Kuerzel,3)=''AOP'' then ''(AO) Ambulantes Operieren'' else ''(ASV) Ambulante Spezialfachaerztliche Versorgung ('' + right(t1.Kuerzel,1) + '')'' end
						when ''E'' then ''(AE) Ambulante Ermächtigung ('' + right(t1.Kuerzel,2) + '')''
						when ''P'' then 
							case when right(t1.Kuerzel,3)=''PAU'' then ''(PAU) Pauschale'' else ''(PAU) Pauschale ('' + right(t1.Kuerzel,2) + '')'' end
						when ''S'' then ''(SPZ) Spezialambulanz''
						else concat(''('',t1.Typ,'') '', t2.KurzText) 
					end 
				else 
					case when right(t1.Kuerzel,3)=''-VN'' then ''(VN) Vor- und Nachstationär'' 
						 else concat(''('',t1.Typ,'') '', t2.KurzText) 
					end 
				end as Typ

				,case  left(t1.Kuerzel,3) 
					when ''TMB'' then ''Tumorboard''
					when ''VSO'' then ''Sozialdienst''
				else 
					case substring(t1.Kuerzel,4,1)
						when ''L'' then ''Labor''
						when ''T'' then ''Therapie''
						when ''D'' then ''Diagnostik''
						when ''O'' then ''OP''
						when ''S'' then ''Station''
						when ''R'' then ''Radiologie''
						when ''A'' then ''Ambulanz''
						when ''F'' then ''Forschung''
						when ''V'' then ''Sonstiges''
					else 
						case  t1.Typ
							when ''K'' then ''Klinik/Institution''
							when ''U'' then ''Bereich''
							when ''A'' then ''Ambulanz''
							when ''S'' then ''Station''
							when ''S1'' then ''Station''
							when ''FU'' then ''Funktionsbereich''
							when ''FL'' then ''Forschung''
							when ''FB'' then ''Fachbereich/-abteilung''
							when ''F'' then ''Fachbereich/-abteilung''
							when ''V'' then ''Sonstiges''
							when ''X'' then ''Sonstiges''
							when ''D'' then ''Sonstiges''
						else 
							t1.Typ 
						end
					end
				 end as Typ_Bereich
				,t2.KurzText as Typ_Text
				,t1.Name
				,t1.Kuerzel
				,t1.Zugehoerigkeit
				,t1.Klinikbereich
				,t1.Belegabteilung
				,t1.Fachabteilung
				,t1.Pflegebereich
				,t1.Intensiv
				,t1.Ambulant
				,t1.Fachrichtung
				,t1.Fachrichtung1
				,t1.Fachrichtung2
				,t1.Fachrichtung3
				,t1.ist_gesperrt'
		End
end;



			