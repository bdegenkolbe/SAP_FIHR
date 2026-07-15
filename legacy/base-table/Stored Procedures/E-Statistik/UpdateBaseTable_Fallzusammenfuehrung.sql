USE [Analysen]
GO

--exec dbo.[UpdateBaseTable_Fallzusammenfuehrung] @Ladeverfahren = 'D',@MaxDelay=1,@CDPOS_Laden=0,@TEMPLoeschen=1,@TEMPPraefix=134202952, @PreProcessing=1, @MainProcessing=1, @PostProcessing=1
--Select * from Fallzusammenfuehrung_Fall_RAW where FallID='10000010017230769'
--Select * from Fallzusammenfuehrung_Fall where FallID='10000010017230769'
--Select * from Fallzusammenfuehrung_Bewegung where FallID='10000010017230769'

CREATE or ALTER PROC [dbo].[UpdateBaseTable_Fallzusammenfuehrung]
	@DELAY int						=60,	--> Greift im Fasttrack auch die Daten n-Tage vor dem letzten Ladevorgang ab. 
	@MaxDelay	as int				=0,		--> Maximale Verzögerung des letzten Aktualisierung einer Quelltabelle in Minuten. Insofern 0 oder negative Zahlen verwendet werden, bezieht sich die Verzögerung auf Tage. (0 die Aktualisierung muss von heute sein, -1 die Aktualisierung muss von gestern sein)
	@DaysToFullLoad int				=7,		--> Aller wieviel Tage soll ein Fullload durchgeführt werden?
	@TestLoop nvarchar(100)			='',	--> bspw. 'Top 100' für 100 Testdatensätze
	@DeltaDays as int				=1,		--> Delta-Load beinhaltet n volle Tage 
	@FullloadYears as int			=5,		--> Jahre die als Fullload geladen werden sollen, 0=Delta-Load
	@Ladeverfahren as nvarchar(2)	='',	--> Wenn 'F' dann Fulload, wenn 'D' dann Deltaload, Sonst entscheidet das Skript automatische über das Ladeverfahren anhand der Einstellungen
	@CDPOS_laden as int				=0,		--> Wenn 1 wird die CDPOS bei Änderungen geladen, wenn 2 wird CDPOS immer geladen, wenn 0 wird CDPOS nicht geladen
	@LastChangeFromTarget as int	=0,		--> Wenn 1 wird der letzte Änderungszeitpunkt aus der TargetTabelle berechnet - langsam/0=Änderungszeitpunkt wird aus den SYS-Tabellen berechnet
	@HashAbgleich_ct as int			=0,		--> 1=Nur relevanten Änderungen in den ct Tabellen werden mit einem HASH über die ausgewählten Spalten verarbeitet/0=keine Hash-Prüfung im ersten Schritt
	@Historisierung as int			=0,		--> 1=Historisierte Werte aus CT-Tabellen und der CDPOS werden abgefragt / 0=keine historisierten Werte
	@PreProcessing as int			=1,		--> 1=Vorprozesse werden ausgeführt
	@MainProcessing as int			=1,		--> 1=Hauptprozesse werden ausgeführt
	@PostProcessing as int			=1,		--> 1=Nachprozesse werden ausgeführt
	@TEMPPraefix as nvarchar(100)	='New',	--> 'New' wird eine neue TempID für alle Temptabellen vergeben. Insofern ein Wert für @TEMPPraefix=108512190 angegeben wird, wird dieser Wert für alle Temp-Tabellen verwendet.
	@TEMPLoeschen as int			=0,		--> 1=Tempdateien werden gelöscht
	@StartStep as varchar(10)		='',	--> Startet mit Prozessschritt bspw. 'XP270'
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
	DECLARE @SQL_TableTargetName as nvarchar(200)	
	DECLARE @CDPOS_TableID as nvarchar(200)
	DECLARE @SQL as nvarchar(max)

	SET @SQL_TableSourceDB			= 'replicate'
	SET @SQL_TableSourceSchema		= 'sap'

	if @MainProcessing=1
		Begin
			
			SET	@SQL_TableSource_Join=Concat('
							left join ',@SQL_TableSourceDB,'.',@SQL_TableSourceSchema,'.NAPX_FAL t2 on |x|APXNR=t2.APXNR
							left join ',@SQL_TableSourceDB,'.',@SQL_TableSourceSchema,'.NAPX_FAL t3 on |x|APXNR=t3.APXNR and t3.LEAD=''X''')
			SET	@SQL_TableTarget_Join=Concat('
							left join ',@SQL_TableSourceDB,'.',@SQL_TableSourceSchema,'.NAPX_FAL t2 on |x|APXNR=t2.APXNR
							left join ',@SQL_TableSourceDB,'.',@SQL_TableSourceSchema,'.NAPX_FAL t3 on |x|APXNR=t3.APXNR and t3.LEAD=''X''')
							
			Execute dbo.UpdateBaseTable_Aenderungshistorie
				@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@CDPOS_laden=@CDPOS_laden,
				@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
				@SQL_TableSourceDB= @SQL_TableSourceDB, @SQL_TableSourceSchema= @SQL_TableSourceSchema,
				@SQL_TableSourceName='NAPX',
				@SQL_TableSourceFields='MANDT,EINRI,APXNR,FALNR,LEAD,REASON',
				@SQL_TableSource_Join=@SQL_TableSource_Join,
				@SQL_TableSourceID='concat(|x|MANDT,t2.EINRI,t2.FALNR)',
				@SQL_TableSourceCreateDate='case when try_cast(|x|ERDAT as datetime)>0 then cast(|x|ERDAT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end',
				@SQL_TableSourceUpDate='case when try_cast(|x|UPDAT as datetime)>0 then cast(|x|UPDAT as datetime) else case when try_cast(|x|ERDAT as datetime)>0 then cast(|x|ERDAT as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end end',
				@SQL_TableSourceStornoDate='case when |x|STORN=''X'' and try_cast(|x|STDAT as datetime)>0 then cast(|x|STDAT as datetime) else cast(''31.12.2099 23:59:59'' as datetime) end',
				@SQL_TableSourceStornoFlag='case when |x|STORN=''X'' then 1 else 0 end',	@ValidToStorno	= 1,
				@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
				@SQL_TableTargetName='Fallzusammenfuehrung_Fall',
				@SQL_TableTargetID='|x|FallID',
				@SQL_TableTargetDefinition1='
				cast(|x|APXNR as bigint)						as AbrechnungID
				,cast(t3.FALNR as bigint)						as Fallnummer
				,concat(|x|MANDT, t2.EINRI, t2.FALNR)			as FallID_Alt
				,cast(t2.FALNR as bigint)						as Fallnummer_Alt
				,t2.REASON										as Grund
				,case t2.REASON
					when ''RV'' then ''Rückverlegung''
					when ''WA'' then ''Wiederaufnahme''
					when ''KO'' then ''Komplikation''
					when ''OG'' then ''Wiederaufnahme nach §2(1) FPV''
					when ''MD'' then ''Wiederaufnahme nach §2(2) FPV''
					when ''WP'' then ''Wiederaufnahme Psychiatrie/Psychosomatik''
					when ''RP'' then ''Rückverlegung Psychiatrie/Psychosomatik''
					else ''Sonstiges'' end						as Grund_Kurztext
				,case when isnull(t2.LEAD,0) =''X'' then 1 else 0 end as Fall_ist_fuehrend
				',
				@SQL_TableSource_Where='|x|STDAT<>|x|ERDAT',
				--@CDPOS_laden=1, @CDPOS_TableID	= 'concat(|x|MANDANT,|x|OBJECTID)',
				@SQL_TableTarget_Join=@SQL_TableTarget_Join,
				@SQL_TableTarget_Where = ''

			SET	@SQL_TableTarget_Join=Concat('
			left join ',@SQL_TableSourceDB,'.',@SQL_TableSourceSchema,'.NAPX_FAL tFall on |x|MANDT=tFall.MANDT and |x|EINRI=tFall.EINRI and |x|APXNR=tFall.APXNR and tFall.LEAD=''X''
			left join (Select CONCAT(MANDT,EINRI,APXNR,FALNR_OLD,LFDBEW_OLD) as APXID, 1 as Split
					from Replicate.sap.NAPX_BEW
					group by MANDT,EINRI,APXNR,FALNR_OLD,LFDBEW_OLD
					having COUNT(*)>1) tSplit on CONCAT(|x|MANDT,|x|EINRI,|x|APXNR,|x|FALNR_OLD,|x|LFDBEW_OLD)=tSplit.APXID 
			')

			SET	@SQL_TableSource_Join = Concat(' 
			join ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NAPX_FAL tFall on |x|MANDT=tFall.MANDT and |x|EINRI=tFall.EINRI and |x|APXNR=tFall.APXNR and tFall.LEAD=''X''
			join ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NAPX tAPX on |x|MANDT=tAPX.MANDT and |x|APXNR=tAPX.APXNR
			
			')

			Execute dbo.UpdateBaseTable_Aenderungshistorie
				@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen,
				@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
				@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
				@SQL_TableSourceName='NAPX_BEW',
				@SQL_TableSourceFields='MANDT,EINRI,APXNR,LFDBEW_NEW,BEWTY_NEW,FALNR_OLD,LFDBEW_OLD,STORN',
				@SQL_TableSourceID='concat(|x|MANDT,|x|EINRI,tFall.FALNR,|x|LFDBEW_NEW)',
				@SQL_TableSourceCreateDate='case when try_cast(tAPX.ERDAT as datetime)>0 then cast(tAPX.ERDAT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end',
				@SQL_TableSourceUpDate='case when try_cast(tAPX.UPDAT as datetime)>0 then cast(tAPX.UPDAT as datetime) else case when try_cast(tAPX.ERDAT as datetime)>0 then cast(tAPX.ERDAT as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end end',
				@SQL_TableSourceStornoDate='case when tAPX.STORN=''X'' and try_cast(tAPX.STDAT as datetime)>0 then cast(tAPX.STDAT as datetime) else cast(''31.12.2099 23:59:59'' as datetime) end',
				@SQL_TableSourceStornoFlag='case when tAPX.STORN=''X'' then 1 else 0 end',	@ValidToStorno	= 1,
				@SQL_TableSource_Join=@SQL_TableSource_Join,
				@SQL_TableSource_Where='tAPX.STDAT<>tAPX.ERDAT',
				@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
				@SQL_TableTargetName='Fallzusammenfuehrung_Bewegung',
				@SQL_TableTargetID='|x|BewegungID',
				@SQL_TableTargetDefinition1='cast(|x|APXNR as bigint)			as AbrechnungID
				,concat(|x|MANDT, |x|EINRI, tFall.FALNR)						as FallID
				,cast(tFall.FALNR as bigint)									as Fallnummer
				,cast(|x|LFDBEW_NEW as int) 									as Bewegung_Nummer
				,|x|BEWTY_NEW													as Bewegung_Typ
				,concat(|x|MANDT,|x|EINRI,|x|BEWTY_NEW)							as Bewegung_TypID
				,isnull(tSplit.Split,0)											as Bewegung_Typ_Split37
				,concat(|x|MANDT, |x|EINRI, |x|FALNR_OLD)						as FallID_Alt
				,concat(|x|MANDT, |x|EINRI, |x|FALNR_OLD, |x|LFDBEW_OLD)		as BewegungID_Alt
				,cast(|x|FALNR_OLD as bigint)									as Fallnummer_Alt
				,cast(|x|LFDBEW_OLD as int)										as Bewegung_Nummer_Alt
				,case when |x|STORN=''X'' then 1 else 0 end						as Bewegung_ist_storniert
				,case when |x|FALNR_OLD=isnull(tFall.FALNR,0) then 1 else 0 end	as Fall_ist_fuehrend
				',
				--@CDPOS_laden=1, @CDPOS_TableID	= 'concat(|x|MANDANT,|x|OBJECTID)',
				@SQL_TableTarget_Join=@SQL_TableTarget_Join,
				@SQL_TableTarget_Where = ''

			SET	@SQL_TableTarget_Join=Concat('
			left join ',@SQL_TableSourceDB,'.',@SQL_TableSourceSchema,'.NAPX_FAL tFall on |x|MANDT=tFall.MANDT and |x|APXNR=tFall.APXNR and tFall.LEAD=''X''
			join ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NAPX_BEW tBew on |x|MANDT=tBew.MANDT and |x|APXNR=tBew.APXNR and |x|LFDBEW_NEW=tBew.LFDBEW_NEW
			')

			SET	@SQL_TableSource_Join = Concat(' 
			join ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NAPX_FAL tFall on |x|MANDT=tFall.MANDT and |x|APXNR=tFall.APXNR and tFall.LEAD=''X''
			join ', @SQL_TableSourceDB,'.',@SQL_TableSourceSchema, '.NAPX tAPX on |x|MANDT=tAPX.MANDT and |x|APXNR=tAPX.APXNR
			')
			Execute dbo.UpdateBaseTable_Aenderungshistorie
				@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen,
				@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
				@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
				@SQL_TableSourceName='NAPX_DIA',
				@SQL_TableSourceFields='MANDT,APXNR,LFDNR_NEW,LFDBEW_NEW,LFDNR_OLD,DRG_DIA_SEQNO,DRG_CATEGORY,DRG_RELVANT,CCL,STORN',
				@SQL_TableSourceID='concat(|x|MANDT,tFall.EINRI,tFall.FALNR,|x|LFDNR_NEW)',
				@SQL_TableSourceCreateDate='case when try_cast(tAPX.ERDAT as datetime)>0 then cast(tAPX.ERDAT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end',
				@SQL_TableSourceUpDate='case when try_cast(tAPX.UPDAT as datetime)>0 then cast(tAPX.UPDAT as datetime) else case when try_cast(tAPX.ERDAT as datetime)>0 then cast(tAPX.ERDAT as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end end',
				@SQL_TableSourceStornoDate='case when tAPX.STORN=''X'' and try_cast(tAPX.STDAT as datetime)>0 then cast(tAPX.STDAT as datetime) else cast(''31.12.2099 23:59:59'' as datetime) end',
				@SQL_TableSourceStornoFlag='case when tAPX.STORN=''X'' then 1 else 0 end',	@ValidToStorno	= 1,
				@SQL_TableSource_Join=@SQL_TableSource_Join,
				@SQL_TableSource_Where='tAPX.STDAT<>tAPX.ERDAT',
				@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
				@SQL_TableTargetName='Fallzusammenfuehrung_Diagnosen',
				@SQL_TableTargetID='|x|DiagnoseID',
				@SQL_TableTargetDefinition1='cast(|x|APXNR as bigint)			as AbrechnungID
				,concat(tBew.MANDT,tBew.EINRI,tBew.FALNR_OLD,|x|LFDNR_OLD)		as DiagnoseID_Alt
				,concat(|x|MANDT, tFall.EINRI, tFall.FALNR)						as FallID
				,concat(|x|MANDT, tBew.EINRI, tBew.FALNR_OLD)					as FallID_Alt
				,concat(|x|MANDT, tFall.EINRI, tFall.FALNR, |x|LFDBEW_NEW)		as BewegungID
				,concat(|x|MANDT, tBew.EINRI, tBew.FALNR_OLD, tBew.LFDBEW_OLD)	as BewegungID_Alt
				,cast(|x|LFDNR_NEW as int) 										as Diagnose_Nummer
				,cast(|x|LFDNR_OLD as int) 										as Diagnose_Nummer_Alt
				,cast(|x|DRG_DIA_SEQNO as int) 									as Diagnose_DRG_SeqNummer
				,|x|DRG_CATEGORY												as Diagnose_DRG_Kategorie
				,case [DRG_CATEGORY] 
					when ''S'' then ''Nebendiagnose (S)''
					when ''P'' then ''Hauptdiagnose (P)''
					else ''keine DRG-Diagnose'' end								as Diagnose_DRG_Kategorie_KurzText
				,case when |x|DRG_RELVANT=''X'' then 1 else 0 end				as Diagnose_DRG_Relevant
				,cast(|x|CCL as int) 											as Diagnose_DRG_CCL
				,case when |x|STORN=''X'' then 1 else 0 end						as Diagnose_ist_storniert
				',
				--@CDPOS_laden=1, @CDPOS_TableID	= 'concat(|x|MANDANT,|x|OBJECTID)',
				@SQL_TableTarget_Join=@SQL_TableTarget_Join,
				@SQL_TableTarget_Where = ''

			Execute dbo.UpdateBaseTable_Aenderungshistorie
				@DELAY=@DELAY,@MaxDelay=@MaxDelay,@DaysToFullLoad=@DaysToFullLoad,@DeltaDays=@DeltaDays,@FullloadYears=@FullloadYears,@Ladeverfahren=@Ladeverfahren,@TEMPPraefix = @TEMPPraefix, @TEMPLoeschen = @TEMPLoeschen,
				@LastChangeFromTarget=@LastChangeFromTarget,@HashAbgleich_ct=@HashAbgleich_ct,@Historisierung=@Historisierung,
				@SQL_TableSourceDB=@SQL_TableSourceDB,@SQL_TableSourceSchema=@SQL_TableSourceSchema,
				@SQL_TableSourceName='NAPX_ICP',
				@SQL_TableSourceFields='MANDT,APXNR,LNRIC,LFDBEW_NEW,DRG_SEQNO,DRG_CATEGORY,DRG_RELEVANT,STORN',
				@SQL_TableSourceID='concat(|x|MANDT,|x|LNRIC)',
				@SQL_TableSourceCreateDate='case when try_cast(tAPX.ERDAT as datetime)>0 then cast(tAPX.ERDAT as datetime) + cast(''00:00:00'' as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end',
				@SQL_TableSourceUpDate='case when try_cast(tAPX.UPDAT as datetime)>0 then cast(tAPX.UPDAT as datetime) else case when try_cast(tAPX.ERDAT as datetime)>0 then cast(tAPX.ERDAT as datetime) else cast(''1.1.1990 00:00:00'' as datetime) end end',
				@SQL_TableSourceStornoDate='case when tAPX.STORN=''X'' and try_cast(tAPX.STDAT as datetime)>0 then cast(tAPX.STDAT as datetime) else cast(''31.12.2099 23:59:59'' as datetime) end',
				@SQL_TableSourceStornoFlag='case when tAPX.STORN=''X'' then 1 else 0 end',	@ValidToStorno	= 1,
				@SQL_TableSource_Join=@SQL_TableSource_Join,
				@SQL_TableSource_Where='tAPX.STDAT<>tAPX.ERDAT',
				@SQL_TableTargetDB=@SQL_TableTargetDB,@SQL_TableTargetSchema=@SQL_TableTargetSchema,
				@SQL_TableTargetName='Fallzusammenfuehrung_Operationsschluessel',
				@SQL_TableTargetID='|x|OperationsschluesselID',
				@SQL_TableTargetDefinition1='cast(|x|APXNR as bigint)			as AbrechnungID
				,concat(|x|MANDT, tFall.EINRI, tFall.FALNR)						as FallID
				,concat(|x|MANDT, tFall.EINRI, tFall.FALNR, |x|LFDBEW_NEW)		as BewegungID
				,cast(|x|LNRIC as bigint) 										as Operationsschluessel_Nummer
				,cast(|x|DRG_SEQNO as int) 									as Operationsschluessel_DRG_SeqNummer
				,|x|DRG_CATEGORY												as Operationsschluessel_DRG_Kategorie
				,case when |x|STORN=''X'' then 1 else 0 end						as Operationsschluessel_ist_storniert
				',
				--@CDPOS_laden=1, @CDPOS_TableID	= 'concat(|x|MANDANT,|x|OBJECTID)',
				@SQL_TableTarget_Join=@SQL_TableTarget_Join,
				@SQL_TableTarget_Where = ''
		end


	if @PostProcessing=1
		Begin
			Print '@PostProcessing'
		End
end

