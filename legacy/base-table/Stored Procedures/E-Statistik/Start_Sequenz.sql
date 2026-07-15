Print 'xxxxxxxx UpdateBaseTable_Falldaten_Aenderungshistorie xxxxxxxxxxxxxxxxxxx'
exec dbo.UpdateBaseTable_Falldaten_Aenderungshistorie @Ladeverfahren = 'FN', @PreProcessing=1, @MainProcessing=1, @PostProcessing=1, @TEMPLoeschen=1
Print 'xxxxxxxx UpdateBaseTable_Bewegungen_Aenderungshistorie xxxxxxxxxxxxxxxxxxx'
exec dbo.UpdateBaseTable_Bewegungen_Aenderungshistorie @Ladeverfahren = 'FN', @PreProcessing=1, @MainProcessing=1, @PostProcessing=1, @TEMPLoeschen=1
Print 'xxxxxxxx UpdateBaseTable_Leistungen_Aenderungshistorie xxxxxxxxxxxxxxxxxxx'
exec dbo.UpdateBaseTable_Leistungen_Aenderungshistorie @Ladeverfahren = 'FN', @PreProcessing=1, @MainProcessing=1, @PostProcessing=1, @TEMPLoeschen=1
Print 'xxxxxxxx UpdateBaseTable_Diagnosen_Aenderungshistorie xxxxxxxxxxxxxxxxxxx'
exec dbo.UpdateBaseTable_Diagnosen_Aenderungshistorie @Ladeverfahren = 'FN', @PreProcessing=1, @MainProcessing=1, @PostProcessing=1, @TEMPLoeschen=1