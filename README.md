# sisyphus

[![Build Status](https://travis-ci.org/Molmed/sisyphus.png?branch=master)](https://travis-ci.org/Molmed/sisyphus)

Sisyphus är en samling skript och moduler i huvudsak skrivna i Perl för att automatisera och på andra sätt underlätta kopiering, bearbetning och analys av data från Illuminas HiSeq2500, HiSeqX och MiSeq. Sisyphus kan grovt delas in i fyra delar: 
 - Postprocessning av data från bcl till (demultiplexade) FASTQ-filer
 - Kopiering av data från lokal server till plattformens projekt på UPPMAX
 - Packning och filtrering av runfolder för arkivering och leverans
 - Verktyg för sammanställning av statistik, filtrering av sekvens etc 

Användardokumentation för perlskript och perlmoduler är tillgänglig med kommandot perldoc för respektive fil. Program/skript skrivna i andra språk är dokumenterade antingen i form av en längre kommentar i början av filen eller i underkatalogen ”doc”.

## Förhandskrav

### Uppmax host
- gnuplot
- gzip
- binary
- ImageMagick
- md5sum
- OpenSSH
- Perl
- rsync
- tar
- Perlmoduler:
    * Digest::MD5
    * PerlIO::gzip
    * XML::Simple
    * Archive::Zip
    * PDL
    * File::NFSLock

### Lokal server (testat på Scientific Linux 6.8)
- gzip
- Bcl2fastq-v2.19
- md5sum
- OpenSSH
- Perl
- Rsync
- dos2unix
- Perlmoduler:
    * Digest::MD5
    * PerlIO::gzip
    * XML::Simple
    * Archive::Zip
    * File::NFSLock
## MiSeq
Microsoft File Checksum Integrity Verifier V2.05 (fciv)

## Installation

Ladda ner Sisyphus till din lokala server:

`git clone https://github.com/Molmed/sisyphus`

I denna guide kommer det antas att sisyphus klonats till `/srv/sisyphus`

### Installation på Uppmax
För att fungera på Uppmax måste de program och moduler som listats ovan (”Förhandskrav”) vara tillgängliga i användarens sökvägar för program (PATH) och perlbibliotek (PERL5LIB). De skript som behöver det försöker ladda de relevanta modulerna (uppmax, gnuplot och irods/swestore) via Uppmax modulsystem. Dock finns inte Perl PDL installerat på Uppmax och därför har Sisyphus en funktion för att konfigurera extra sökvägar till bibliotek så att PDL och eventuella andra moduler kan installeras till en valfri mapp. PDL och alla dess beroenden (primärt beroenden för själva installationsprocessen), installeras med de kommandon som finns listade i filen INSTALL_PDL_milou.txt i sisyphus-mappen. Det går också att installera PDL via CPAN, men installationen hamnar då i användarens hemkatalog om det inte installeras av root, vilket inte är önskvärt om flera användare ska köra sisyphus. Var modulerna installerats anges under PERL5LIB i sisyphus.yml. 

### Installation på MiSeq
För att kunna köra skriptet som kopierar en analysmapp från MiSeq-instrumentet till avsedd plats på biotanken så behöver, förutom själva skriptet, de program listade ovan (”Förhandskrav”) finnas tillgängliga i användarens PATH.
Följ följande steg för att installera skriptet:
1. Hämta MiSeqAnalysisTransfer.bat från den aktuella sisyphuskoden och placera den i mappen `C:\Users\sbsuser\Documents\Sisyphus\`.
2. Lägg till skriptet i ”SendTo”-menyn:
    1. Öppna ett utforskarfönster och navigera till ovanstående mapp
    2. Högerklicka på MiSeqAnalysisTransfer.bat och välj ”Create shortcut”.
    3. Högerklicka på den nyskapade genvägen (MiSeqAnalysisTransfer.bat - shortcut) och välj ”Rename”. Döp genvägen till namnet på den lokala servern, till exempel "biotank".
    4. Högerklicka sedan på den och välj ”Cut”. Gå till adressfältet i utforskarfönstret och gå till `%APPDATA%\Microsoft\Windows\SendTo`. Högerklicka i fönstret och välj ”Paste”.

### Seq-Summaries
En kopia av diverse statistik (bland annat mappen InterOp) från runfoldern kopieras till den sökväg som angetts under SUMMARY_HOST + SUMMARY_PATH i sisyphus.yml. Till denna mapp ska även mappen Summary som skapats i runfoldern på UPPMAX kopieras. Detta kan göras genom ett cron-jobb på SUMMARY_HOST som regelbundet kör skriptet `sisyphus/getSummary.pl` för alla runfolders som kopierats till SUMMARY_HOST. 

## Användning
```
cd <runfolder>
cp /srv/sisyphus/sisyphus.yml .
cp /srv/sisyphus/sisyphus_qc.xml .
/srv/sisyphus/sisyphus.pl -runfolder $PWD  
```
Flagga | Beskrivning
--- | ---
**-runfolder** | Sökväg till den runfolder som ska processas
**-noexec** | Generera sisyphus.sh skriptet och exekvera det inte
**-nowait** | Vänta inte 30 min med att starta
**-force** | Processa runfolder även om data saknas 
**-miseq** | Anger att ”MiSeq Reporter” mapp ska laddas upp
**-ignoreQCResult** | Processning körs utan att avbryta när QC-resultatet inte uppfylls
**-noUppmaxProcessing** | Ingen data kommer laddas upp till Uppmax och inga jobb kommer startas på Uppmax
**-noSeqStatSync** | Ingen sekvenseringsstatistik kommer laddas upp till SUMMARY_HOST
**-debug** | sisyphus skriver ut extra information i terminalen

Detta är den normala användningen där alla steg i processningen av en runfolder görs automatiskt med skriptet `sisyphus.pl` enligt konfigurationsfilen sisyphus.yml som placerats i runfoldern. `Sisyphus.pl` skapar ett bash-skript i runfoldern som därefter startas automatiskt. Om man behöver göra några förändringar i bash-skriptet, t.ex. om antalet cykler som används för demultiplexning behöver justeras, innan det körs startar man `sisyphus.pl` med flaggan `--noexec`.

Innan kopieringen till Uppmax startas kommer Sisyphus att automatiskt kontrollera resultaten som hittas i den korta sammanfattningen (quickReport) som genereras. Om allt stämmer med angivna QC-kriterier (sisyphus_qc.xml) kommer data att laddas upp på Uppmax och rapporten skickas till maillistan som är angiven i sisyphus.yml.

### Konfiguration
I konfigurationsfilen sisyphus.yml anges sökväg till bcl2fastq, serveradress, kataloger och projektallokering för UPPMAX, samt en mejladress för att notifiera ansvariga för processning. 

Sisyphus kan verifiera att en runfolder är arkiverad på två olika sätt (se "Delprocesser/moduler" nedan). Genom att ändra `USE_SSVERIFY: 1` till `USE_SSVERIFY: 0` kommer sisyphus egen arkiveringsverifiering användas istället för ssverify som är en verifieringsmetod skriven av Uppmax.

Indexcheck (se "Delprocesser/moduler") kan utföras innan demultiplexning genom att ändra `PRE_DEMULTIPLEX_INDEX_CHECK: 0` till `PRE_DEMULTIPLEX_INDEX_CHECK: 1`.

### MiSeq Reporter
För MiSeq-körningar är det i vissa fall önskvärt att även leverera en komplett runfolder som kan öppnas och analyseras i Illuminas mjukvara ”MiSeq Reporter”. Om detta ska ske så ska MiSeq-operatören efter avslutad sekvensering har kopierat analyskatalogen för körningen från instrumentet till den lokala servern. För att inkludera analyskatalogen vid processning med sisyphus, startar man med flaggan -miseq. Konfigurationsfilen ska även innehålla sökvägen till katalogen som innehåller körningens analyskatalog, relativt körkatalogen. Analyskatalogen kommer då packas ihop till ett komprimerat tar-arkiv och läggas i den ordinarie runfoldern innan denna laddas upp till Uppmax. Observera att analyskatalogen kommer att tas bort från den lokala servern efter att den packats ihop och arkivet verifierats.

### Processning på Uppmax
Processningen på Uppmax kommer automatisk startas efter att data har laddats upp, men kan manuellt startas på Uppmax med följande kommandon.
```
ssh <uppmax host>
cd <runfolder>
./Sisyphus/aeacus-stats.pl –runfolder $PWD 
./Sisyphus/aeacus-reports.pl –runfolder $PWD
```
Slutfasen av processningen skapar rapporter, projektmappar och arkivkopior

### Felsökning
Sisyphus innehåller ett stort antal kontrollsteg och om någon del i processningen skulle misslyckas så avbryts allt och felet måste åtgärdas innan sisyphus startas om. Om delar av processningen är klar kan man starta om från det steg som misslyckades, t.ex. genom att kommentera ut redan avklarade steg i sisyphus.sh. Skripten som startas på Uppmax körs som batch-skript i mappen `<runfolder>/slurmscripts` och loggarna skapas i `<runfolder>/slurmscripts/logs/`.

#### Omprocessning på lokal server
Skulle något fel upptäckas kan processningen göras om från början genom följande steg:
1. De jobb som redan startats på Uppmax (fastqStats) avbryts
2. Runfoldern på Uppmax döps om med ’.old’ i slutet av namnet
3. I runfoldern på den lokala servern tas följande filer/mappar bort
    * Sisyphus/
    * MD5/
    * rsync*.log
    * sisyphus.sh
    * excludedTiles.yml
    * /data/scratch/<runfoldername>
    * setupBclToFastq.err
    * Unaligned
    * Excluded (om den har skapats)
    * quickReport.txt
4. Starta sedan om processningen enligt ovan (se "Användning")


#### Omprocessning på Uppmax
Om någon del i rapportskapandet behöver köras om raderar man följande filer/kataloger i runfoldern på Uppmax.
+ Summary
+ Statistics
+ MD5/sisyphus.md5

I sista steget tas md5summor för filerna bort eftersom man annars riskerar att få problem vid leverans och arkivering. Kör sedan om de uppmax stegen enligt ovan ”Processning på uppmax”.

#### Arkivering
För att arkiveringen ska fungera krävs att inga filer modifierats, dvs md5summorna i MD5/checksums.md5 och MD5/sisyphus.md5 måste stämma. Om någon fil ändrats måste därför den gamla md5summan tas bort innan arkiveringen startas/startas om.
Om verifieringen av swestorekopian av någon anledning misslyckas och behöver göras om så kan man starta om batch-scriptet under `<ARCHIVE_PATH>/ArchiveScripts/`.

### Delprocesser/moduler
I Sisyphus ingår ett antal skript som dels används av huvudskriptet sisyphus.pl, men som även kan köras separat vid behov. En sammanfattning av de olika skripten följer nedan. För full dokumentation hänvisas till dokumentationen för respektive skript i sisyphus-mappen.
* **md5sum.pl** – Läser en lista med filnamn från rsync och beräknar MD5-kontrollsummor för dessa filer.
* **qcValidateRun.pl** – Jämföra QC-parametrar för körningen med definierade krav, och om QC-kriterier inte uppfylls eller inte kan hittas kommer ett mail skickas med information varför körningen inte godkänts.
* **quickReport.pl** – Skapar en kort rapport med de viktigaste QC-parametrarna och mejlar denna till den adress som angivits i konfigurationsfilen.
* **aeacus-stats.pl** – Startar `fastqStats.pl` på klustret med en process per lane.
* **fastqStat.pl** – Sammanställer statistik för varje fastq-fil. Resultatet sparas i form av en zip-fil i mappen Statistics. Dessa filer används sedan vid skapandet av rapporter.
* **aeacus-reports.pl** – Startar `extractProject.pl`, `generateReport.pl` och `archive.pl` på klustret med en process per projekt samt beroenden så att `archive.pl` endast körs om `generateReport.pl` kört klart utan fel vilket i sin tur endast körs om alla projekt processats utan fel.
* **extractProject.pl** – Skapar en projektspecifik rapport för de lanes och prover som tillhör ett specifikt projekt. Mappen skapas i runfoldern under Projects och innehåller hårdlänkade fastq-filer (dvs ingen ny kopia görs utan bara nytt namn på samma fil), rapport och kontrollsummor för alla filer som ska levereras.
* **generateReport.pl** – Skapar en global rapport för hela runfoldern i mappen Summary.
* **archive.pl** – Skapar en kopia av runfoldern för arkivering på det ställe som anvisats i konfigurationsfilen. Alla filer som inte redan är i ett komprimerat format (png,gz,bz2,jpg) samt några få undantagna filer, t.ex. report.html, komprimeras med gzip innan de arkiveras. Om arkivkopian ligger på samma diskvolym som runfoldern så görs hårda länkar till fastq-filerna för att inte duplicera data. Fastq-filerna arkiveras i första hand från projektmapparna och endast om de inte är med i en projektmapp arkiveras de från mappen ”Unaligned”. Alla filer utom de som ligger under Projects samt fastq-filerna kopieras in i en för runfoldern gemensam tar-fil. För respektive projekt skapas separata tar-filer och fastq-filerna inkluderas som de är utan tar i en kopia av runfolderns mappstruktur. Nya filer med kontrollsummor för alla i arkivet ingående filer, både tar-filer, originalfiler och komprimerade filer, skapas också så att arkivets och eventuellt senare återlästa filers integrigtet kan kontrolleras. När arkivet är skapat kontrolleras det genom att alla filer i originalmappen identifieras och verifieras mot arkivet.
* **archive2swestore.pl** – Kopierar arkivmappen till lagring på SweStore för långtidsarkivering. Startar verifiering efter 4 dagar. Om ssverify-verifiering angivits i konfigurationsfilen kommer ssverify.sh anropas, vilket jämför adler32 kontrollsummor mellan alla filer i arkivmappen och motsvarande mapp på SweStore. Om detta alternativ inte har valts kommer istället sisyphus egen verifieringsprocedur användas. Denna procedur laddar ner alla filer från SweStore och kontrollerar att de sparade md5-kontrollsummorna stämmer.  Filer som eventuellt inte kan verifieras laddas upp igen. 
* **gzipFolder.pl** – Tar en katalog och en fil med md5-summor för katalogens innehåll som argument och genererar ett komprimerat tar-arkiv av katalogen (tar.gz). Innehållet i det komprimerade arkivet verifieras mot md5-summorna i den tillhandahållna filen och om allt stämmer så raderas ursprungskatalogen.
* **MiSeqAnalysisTransfer.bat** – Windows batchskript som kopierar en mapp till en inkodad sökväg. Används på MiSeq-instrument för att kopiera en analysmapp till den avsedda platsen på biotanken. Skriptet kan köras från kommandotolken men kan även startas genom att dra-och-släppa en mapp på ikonen för skriptet.
* **getSummary.pl** – Kopierar summary-mappen för en runfolder från Uppmax. Hostname och sökväg hämtas ur runfolderns sisyphus.yml. Om ingen Summary-mapp finns 7 dagar efter att runfoldern skapats på servern där skriptet körs (SUMMARY_HOST) skapas filen noSummary i den lokala mappen och inga fler försök att ladda ner summaryn görs. Ta bort noSummary för att försöka igen. Om ProjMan (extern mjukvara) finns installerat på samma ställe som sisyphus kommer anrop göras för att läsa in report.xml till en databas.
* **checkIndices.pl** – I ett standardflöde anropas skriptet efter demultiplexning för att undersöka om det är något som sticker ut bland ”Undetermined indices”, i.e. index som inte har kunnat kopplas till ett prov. Om ett specifikt index förekommer oftare än 1% av alla reads i en lane, anses det sticka ut. Skriptet tittar då närmare på sådana index och försöker urskönja orsaken till att de ej har kunnat kopplas till något prov. Verkar orsaken vara läsningsfel av sekvenseringsmaskinen anses det vara OK. I andra fall termineras processen och eventuellt funnen orsak skrivs ut (e.g. reverskomplement av index har angivits i SampleSheet). Bioinformatiker får då åtgärda felet och köra om. Om orsaken inte kan identifieras får bioinformatiker utreda det ytterligare. Det är även möjligt att konfiguera Sisyphus att utföra indexchecken innan demultiplexning. I detta fall demultiplexas endast en delmängd av all data och indexchecken görs på denna delmängd. Ser allt bra ut utförs sedan demultiplexning på all data.
