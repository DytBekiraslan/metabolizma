// lib/screens/metabolizma_screen.dart
import '../services/persentil_data.dart';
import 'growth_chart_screen.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as pw;
import 'package:flutter/rendering.dart'; 
import 'package:flutter/services.dart'; // <<< TextInputFormatter için gerekli import
import 'package:metabolizma_takip/screens/fa_graph_screen.dart';
import 'package:metabolizma_takip/screens/tyrosine_graph_screen.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../viewmodels/metabolizma_viewmodel.dart';
import '../models/models.dart';
import '../services/patient_service.dart'; 
import '../services/auth_service.dart'; 
import 'dart:math';
import '../widgets/flippable_card.dart';


class MetabolizmaScreen extends StatefulWidget {
  final PatientRecord? initialRecord;
  
  const MetabolizmaScreen({super.key, this.initialRecord});

  @override
  State<MetabolizmaScreen> createState() => _MetabolizmaScreenState();
}

class _MetabolizmaScreenState extends State<MetabolizmaScreen> {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final viewModel = Provider.of<MetabolizmaViewModel>(context, listen: false);
      if (widget.initialRecord != null) {
        viewModel.loadPatientData(widget.initialRecord!);
      } else {
        final savedRecordId = viewModel.currentRecordId;
        viewModel.clearAllData();
        if (savedRecordId != null) {
          viewModel.currentRecordId = savedRecordId;
        }
      }
    });
}

  // --- KAYDETME MANTIKLARI ---
  
  // GÜNCELLENDİ: Hem yerel (SharedPreferences) hem de harici (indirme) kayıt yapılır.
  Future<void> _handleSaveOrUpdate({required bool isNewRecord}) async {
    final viewModel = Provider.of<MetabolizmaViewModel>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final patientService = Provider.of<PatientService>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final currentUser = authService.currentUser;
    final patientName = viewModel.nameController.text.trim();

    if (currentUser == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Hata: Oturum bulunamadı.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (patientName.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Lütfen hasta adı/soyadı girin.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Kayıt başlatılıyor. Harici JSON ve PDF dosyaları için indirme pencereleri açılacaktır...'
        ),
        duration: Duration(seconds: 5),
      ),
    );

    try {
      final currentPercentiles = viewModel.calculatedPercentiles;
      print('DEBUG KAYIT: neyziWeightPercentile = ${currentPercentiles.neyziWeightPercentile}');
      print('DEBUG KAYIT: whoWeightPercentile = ${currentPercentiles.whoWeightPercentile}');
      
      final saveData = await viewModel.prepareSaveData(currentUser.userId);
      final PatientRecord newRecord = saveData.record;
      
      final PatientRecord savedRecord;
      if (isNewRecord) {
        savedRecord = await patientService.savePatientRecord(newRecord);
        viewModel.setCurrentRecordId(savedRecord.recordId!);
      } else {
        final existingRecordId = viewModel.currentRecordId;
        if (existingRecordId == null) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Hata: Mevcut kayıt ID bulunamadı.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        newRecord.recordId = existingRecordId;
        savedRecord = await patientService.savePatientRecord(newRecord);
      }
      
      final pheLevelText = viewModel.pheLevelController.text;
      final pheLevel = double.tryParse(pheLevelText.replaceAll(',', '.')) ?? 0.0;
      final visitDate = viewModel.visitDate;
      
      if (visitDate != null && patientName.isNotEmpty) {
        final newPheRecord = PhenylalanineRecord(
          patientId: savedRecord.recordId!,
          patientName: patientName,
          visitDate: visitDate,
          pheLevel: pheLevel,
        );
        await patientService.savePheRecord(patientName, newPheRecord);
      }

      final tyrosineLevelText = viewModel.tyrosineLevelController.text;
      final tyrosineLevel = double.tryParse(tyrosineLevelText.replaceAll(',', '.')) ?? 0.0;
      final tyrosineVisitDate = viewModel.tyrosineVisitDate;
      
      if (tyrosineVisitDate != null && patientName.isNotEmpty) {
        final newTyrosineRecord = TyrosineRecord(
          patientId: savedRecord.recordId!,
          patientName: patientName,
          visitDate: tyrosineVisitDate,
          tyrosineLevel: tyrosineLevel,
        );
        await patientService.saveTyrosineRecord(patientName, newTyrosineRecord);
      }
      
      String externalJsonPath = '';
      String externalPdfPath = '';
      
      final dateStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final baseFileName = '${patientName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}_Takip_$dateStr';
      
      try {
        final String? jsonPath = await FileSaver.instance.saveFile(
          name: baseFileName,
          bytes: saveData.jsonBytes,
          ext: 'json',
          mimeType: MimeType.json,
        );
        externalJsonPath = jsonPath ?? 'İptal Edildi';
      } catch (e) {
        final message = e.toString();
        externalJsonPath = 'HATA: ${message.substring(0, min(50, message.length))}';
      }

      if (saveData.pdfBytes != null) {
        try {
          final String? pdfPath = await FileSaver.instance.saveFile(
            name: baseFileName,
            bytes: saveData.pdfBytes!,
            ext: 'pdf',
            mimeType: MimeType.pdf,
          );
          externalPdfPath = pdfPath ?? 'İptal Edildi';
        } catch (e) {
          final message = e.toString();
          externalPdfPath = 'HATA: ${message.substring(0, min(50, message.length))}';
        }
      }

      savedRecord.pdfFilePath = externalPdfPath;
      savedRecord.jsonFilePath = externalJsonPath;

      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            '${patientName} için verileriniz başarıyla kaydedildi (Yerel ve Harici):\n'
            '- JSON Harici İndirme: ${externalJsonPath.contains('HATA') ? externalJsonPath : (externalJsonPath.isNotEmpty ? 'Kaydedildi' : 'İptal Edildi')}\n'
            '- PDF Harici İndirme: ${externalPdfPath.contains('HATA') ? externalPdfPath : (externalPdfPath.isNotEmpty ? 'Kaydedildi' : 'İptal Edildi/Oluşturulamadı')}'
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 10),
        ),
      );

      Navigator.of(context).pop();
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('GENEL KAYIT HATASI: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MetabolizmaViewModel>();
    final isNewPatient = widget.initialRecord == null;
    
    final isExistingRecord = viewModel.currentRecordId != null;

    if (viewModel.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    bool showEnerji2 = viewModel.enerjiReq2CalculationString != "-";
    bool showEnerji3 = viewModel.enerjiReq3CalculationString != "-";
    bool showReferenceTable = viewModel.highlightedReferenceRowIndex != -1; 
    bool hasCalculatedPercentiles = viewModel.calculatedPercentiles.bmiPercentile != '-'; 
    bool showPercentileWeightDisplay = viewModel.selectedWeightSource == WeightSource.whoPercentile || viewModel.selectedWeightSource == WeightSource.neyziPercentile;


    return Scaffold(
      appBar: AppBar( 
        title: Text(isNewPatient ? 'Yeni Metabolizma Hesaplaması' : 'Hasta Takibi: ${viewModel.loadedPatientName}'), 
        backgroundColor: Theme.of(context).colorScheme.inversePrimary, 
        actions: [
          if (!isNewPatient && viewModel.currentRecordId != null)
            Tooltip(
              message: "Kayıt ID: ${viewModel.currentRecordId}",
              child: const Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: Center(child: Icon(Icons.check_circle_outline, color: Colors.green)),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        controller: viewModel.scrollController, 
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Kişisel Bilgiler ---
            _buildSectionTitle(context, 'Kişisel Bilgiler'),
            
            // YENİ: İKİ SÜTUNLU YAPI BAŞLANGICI
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // SOL SÜTUN: Ad Soyad, Boy, Doğum Tarihi, FAF, Prematüre
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTextField(viewModel.nameController, 'Adı Soyadı'),
                      
                      _buildTextField(viewModel.heightController, 'Boy (cm)', inputType: TextInputType.number), 
                      
                      // Doğum Tarihi
                      Tooltip(
                        message: viewModel.calculatedAgeDisplayString == '-'
                            ? 'Doğum tarihi girildiğinde kronolojik yaş hesaplanır.'
                            : 'Kronolojik Yaş: ${viewModel.calculatedAgeDisplayString}',
                        waitDuration: const Duration(milliseconds: 300),
                        child: _buildDatePickerField(context, viewModel),
                      ),
                      
                      _buildTextField(
                          viewModel.fafController, 
                          'Fiziksel Aktivite Faktörü (1.0-2.0)', 
                          inputType: TextInputType.number,
                      ),
                      
                      // Prematüre checkbox
                      _buildCheckbox(context, "Prematüre", viewModel.isPremature, viewModel.setIsPremature),
                    ],
                  ),
                ),
                
                const SizedBox(width: 20),
                
                // SAĞ SÜTUN: Cinsiyet, Ağırlık, Vizit Tarihi, BKİ, Gebe (kadınsa)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildGenderDropdown(context, viewModel),
                      
                      _buildTextField(viewModel.weightController, 'Ağırlık (kg)', inputType: TextInputType.number),
                      
                      // Vizit Tarihi
                      Tooltip(
                        message: 'Vizit tarihi - bu tarihteki ölçümler kaydedilir',
                        waitDuration: const Duration(milliseconds: 300),
                        child: _buildVisitDatePickerField(context, viewModel),
                      ),
                      
                      _buildDisplayField(
                        viewModel.bmiController,
                        'BKİ',
                        tooltipMessage: viewModel.bmiTooltipString,
                      ),
                      
                      // Gebe checkbox (sadece kadın seçildiğinde)
                      if (viewModel.selectedGender == 'Kadın')
                        _buildCheckbox(context, "Gebe", viewModel.isPregnant, viewModel.setIsPregnant),
                    ],
                  ),
                ),
              ],
            ),
            // YENİ: İKİ SÜTUNLU YAPI SONU
            
            // --- Biyokimya Takibi (YENİ BÖLÜM) ---
            const Divider(height: 30),
            _buildSectionTitle(context, 'Biyokimya Takibi'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildTextField(
                    viewModel.pheLevelController,
                    'FA Kan Düzeyi (mg/dL)',
                    inputType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  // FA Tahlil Sonuç Tarihi
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: TextField(
                      controller: viewModel.visitDateController,
                      keyboardType: TextInputType.datetime,
                      onChanged: (value) {
                        if (value.isEmpty) {
                          if (viewModel.visitDate != null) viewModel.setVisitDate(null);
                          return;
                        }
                        if (value.length != 10) return;
                        try {
                          final parsedDate = DateFormat('dd.MM.yyyy').parseStrict(value);
                          if (viewModel.visitDate != parsedDate) viewModel.setVisitDate(parsedDate);
                        } catch (_) {
                          // typing in-progress: don't clear controller
                        }
                      },
                      style: const TextStyle(fontSize: 14.0),
                      inputFormatters: [_DateTextFormatter()],
                      readOnly: false,
                      decoration: InputDecoration(
                        labelText: 'FA Tahlil Sonuç Tarihi (GG.AA.YYYY)',
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue.shade600, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () => viewModel.setVisitDate(null),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Tarihi Temizle',
                            ),
                            // Takvim butonu
                            IconButton(
                              icon: const Icon(Icons.calendar_today, size: 20),
                              onPressed: () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: viewModel.visitDate ?? DateTime.now(),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime(2100),
                                  locale: const Locale('tr', 'TR'),
                                );
                                if (picked != null) viewModel.setVisitDate(picked);
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Takvimi Aç',
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            
            // YENİ EKLENEN KISIM: FA GRAFİĞİ BUTONU
            const SizedBox(height: 15),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final patientName = viewModel.nameController.text.trim();
                  final scaffoldMessenger = ScaffoldMessenger.of(context);

                  if (patientName.isEmpty) {
                     scaffoldMessenger.showSnackBar(
                        const SnackBar(content: Text('Lütfen hasta adı/soyadı girin.'), backgroundColor: Colors.orange)
                     );
                     return;
                  }

                  // Doğum tarihinden yaş hesapla
                  int chronoAgeYears = 0;
                  DateTime? parsedDateOfBirth = viewModel.dateOfBirth;
                  
                  // Eğer controller'da metin varsa, controller'dan parse et (controller güncellenmiş olabilir)
                  if (viewModel.dateOfBirthController.text.isNotEmpty) {
                    try {
                      parsedDateOfBirth = DateFormat('dd.MM.yyyy').parse(viewModel.dateOfBirthController.text);
                    } catch (e) {
                      print("FA Tarih parse hatası: $e");
                    }
                  }
                  
                  if (parsedDateOfBirth != null) {
                    final now = DateTime.now();
                    chronoAgeYears = now.year - parsedDateOfBirth.year;
                    if (now.month < parsedDateOfBirth.month ||
                        (now.month == parsedDateOfBirth.month && now.day < parsedDateOfBirth.day)) {
                      chronoAgeYears--;
                    }
                  }

                  final authService = Provider.of<AuthService>(context, listen: false);
                  final currentUserData = authService.currentUser;

                  // Mevcut PatientRecord'ı oluştur (grafiğe yaş bilgisi geçmek için)
                  final patientRecord = PatientRecord(
                    recordId: viewModel.currentRecordId,
                    ownerUserId: currentUserData?.userId ?? '',
                    patientName: patientName,
                    recordDate: DateTime.now(),
                    recordDataJson: '{}',
                    weight: double.tryParse(viewModel.weightController.text) ?? 0,
                    selectedGender: viewModel.selectedGender,
                    chronologicalAgeInMonths: 0,
                    chronologicalAgeYears: chronoAgeYears,
                    chronologicalAgeMonths: 0,
                  );

                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => FaGraphScreen(
                        patientRecord: patientRecord,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.data_thresholding, size: 18),
                label: const Text('FA Grafiğini Görüntüle'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            // YENİ KISIM SONU

            // YENİ EKLENEN KISIM: TİROZİN KAN DÜZEYİ ALANLARI
            const SizedBox(height: 15),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildTextField(
                    viewModel.tyrosineLevelController,
                    'Tirozin Kan Düzeyi (mg/dL)',
                    inputType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: TextField(
                      controller: viewModel.tyrosineVisitDateController,
                      keyboardType: TextInputType.datetime,
                      onChanged: (value) {
                        if (value.isEmpty) {
                          if (viewModel.tyrosineVisitDate != null) viewModel.setTyrosineVisitDate(null);
                          return;
                        }
                        if (value.length != 10) return;
                        try {
                          final parsedDate = DateFormat('dd.MM.yyyy').parseStrict(value);
                          if (viewModel.tyrosineVisitDate != parsedDate) viewModel.setTyrosineVisitDate(parsedDate);
                        } catch (_) {
                          // typing in-progress
                        }
                      },
                      style: const TextStyle(fontSize: 14.0),
                      inputFormatters: [_DateTextFormatter()],
                      readOnly: false,
                      decoration: InputDecoration(
                        labelText: 'Tirozin Tahlil Sonuç Tarihi (GG.AA.YYYY)',
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue.shade600, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () => viewModel.setTyrosineVisitDate(null),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Tarihi Temizle',
                            ),
                            // Takvim butonu
                            IconButton(
                              icon: const Icon(Icons.calendar_today, size: 20),
                              onPressed: () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: viewModel.tyrosineVisitDate ?? DateTime.now(),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime(2100),
                                  locale: const Locale('tr', 'TR'),
                                );
                                if (picked != null) viewModel.setTyrosineVisitDate(picked);
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Takvimi Aç',
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // TİROZİN GRAFİĞİ BUTONU
            const SizedBox(height: 15),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final patientName = viewModel.nameController.text.trim();
                  final scaffoldMessenger = ScaffoldMessenger.of(context);

                  if (patientName.isEmpty) {
                     scaffoldMessenger.showSnackBar(
                        const SnackBar(content: Text('Lütfen hasta adı/soyadı girin.'), backgroundColor: Colors.orange)
                     );
                     return;
                  }

                  // Doğum tarihinden yaş hesapla
                  int chronoAgeYears = 0;
                  DateTime? parsedDateOfBirth = viewModel.dateOfBirth;
                  
                  // Eğer controller'da metin varsa, controller'dan parse et (controller güncellenmiş olabilir)
                  if (viewModel.dateOfBirthController.text.isNotEmpty) {
                    try {
                      parsedDateOfBirth = DateFormat('dd.MM.yyyy').parse(viewModel.dateOfBirthController.text);
                    } catch (e) {
                      print("Tirozin Tarih parse hatası: $e");
                    }
                  }
                  
                  if (parsedDateOfBirth != null) {
                    final now = DateTime.now();
                    chronoAgeYears = now.year - parsedDateOfBirth.year;
                    if (now.month < parsedDateOfBirth.month ||
                        (now.month == parsedDateOfBirth.month && now.day < parsedDateOfBirth.day)) {
                      chronoAgeYears--;
                    }
                  }

                  final authService = Provider.of<AuthService>(context, listen: false);
                  final currentUserData = authService.currentUser;

                  // PatientRecord oluştur
                  final patientRecord = PatientRecord(
                    recordId: viewModel.currentRecordId,
                    ownerUserId: currentUserData?.userId ?? '',
                    patientName: patientName,
                    recordDate: DateTime.now(),
                    recordDataJson: '{}',
                    weight: double.tryParse(viewModel.weightController.text) ?? 0,
                    selectedGender: viewModel.selectedGender,
                    chronologicalAgeInMonths: 0,
                    chronologicalAgeYears: chronoAgeYears,
                    chronologicalAgeMonths: 0,
                  );

                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => TyrosineGraphScreen(
                        patientRecord: patientRecord,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.data_thresholding, size: 18),
                label: const Text('Tirozin Grafiğini Görüntüle'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            // TİROZİN GRAFİĞİ BUTONU SONU

            const Divider(height: 30),

            // --- Dinamik Grafik Alanı ---
            _buildSectionTitle(context, 'Büyüme ve Gelişme Değerlendirmesi'),
            // GÜNCELLENDİ: Kronolojik yaşı gün, ay, yıl olarak gösterir (SİZİN İSTEĞİNİZ)
            _buildSubHeader(context, "Kronolojik Yaş: " + viewModel.calculatedAgeDisplayString), 

            
            // YENİ: Persentil Sonuçlarını Neyzi (solda) ve WHO (sağda) olarak göster
            Visibility(
              visible: hasCalculatedPercentiles,
              child: Builder(
                builder: (context) {
                  // Merkezi hesaplayıcıdan güncel persentilleri al
                  final persentilResult = viewModel.persentilCalculator.calculateAllPercentiles(
                    chronologicalAgeInMonths: viewModel.currentAgeInMonths,
                    gender: viewModel.selectedGender,
                    weight: viewModel.currentWeight,
                    height: viewModel.currentHeight,
                  );
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ağırlık Persentili - Neyzi (Solda) ve WHO (Sağda) - FLIPPABLE
                      Row(
                        children: [
                          Expanded(
                            child: persentilResult.hasHeightAge
                                ? FlippableCard(
                                    onSideChanged: (isFront) => viewModel
                                        .setWeightCardFace(
                                            PercentileSource.neyzi, isFront),
                                    frontChild: _buildDisplayBoxWithBorder(
                                      context,
                                      'Ağırlık Persentili\nNEYZİ (Kronolojik)',
                                      persentilResult.neyziWeightPercentileChronoAge,
                                      Colors.orange,
                                      viewModel: viewModel,
                                    ),
                                    backChild: _buildDisplayBoxWithBorder(
                                      context,
                                      'Ağırlık Persentili\nNEYZİ (Boy Yaşı)',
                                      persentilResult.neyziWeightPercentileHeightAge,
                                      Colors.orange,
                                      viewModel: viewModel,
                                      useHeightAgeForPercentiles: true,
                                    ),
                                  )
                                : _buildDisplayBoxWithBorder(
                                    context,
                                    'Ağırlık Persentili\nNEYZİ',
                                    persentilResult.neyziWeightPercentileChronoAge,
                                    Colors.orange,
                                    viewModel: viewModel,
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: viewModel.currentAgeInMonths > 120
                                ? _buildDisplayBoxWithBorder(
                                    context,
                                    'Ağırlık Persentili\nWHO',
                                    '10 yaşından büyük çocuklar\niçin BKİ kullanınız',
                                    Colors.blue,
                                    viewModel: viewModel,
                                  )
                                : (persentilResult.hasHeightAge
                                    ? FlippableCard(
                                    onSideChanged: (isFront) => viewModel
                                      .setWeightCardFace(
                                        PercentileSource.who,
                                        isFront),
                                        frontChild: _buildDisplayBoxWithBorder(
                                          context,
                                          'Ağırlık Persentili\nWHO (Kronolojik)',
                                          persentilResult.whoWeightPercentileChronoAge,
                                          Colors.blue,
                                          viewModel: viewModel,
                                        ),
                                        backChild: _buildDisplayBoxWithBorder(
                                          context,
                                          'Ağırlık Persentili\nWHO (Boy Yaşı)',
                                          persentilResult.whoWeightPercentileHeightAge,
                                          Colors.blue,
                                          viewModel: viewModel,
                                          useHeightAgeForPercentiles: true,
                                        ),
                                      )
                                    : _buildDisplayBoxWithBorder(
                                        context,
                                        'Ağırlık Persentili\nWHO',
                                        persentilResult.whoWeightPercentileChronoAge,
                                        Colors.blue,
                                        viewModel: viewModel,
                                      )),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Boy Persentili - Neyzi (Solda) ve WHO (Sağda) - NON-FLIPPABLE
                      Row(
                        children: [
                          Expanded(
                            child: _buildDisplayBoxWithBorder(
                              context,
                              'Boy Persentili\nNEYZİ',
                              persentilResult.neyziHeightPercentile,
                              Colors.orange,
                              viewModel: viewModel,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildDisplayBoxWithBorder(
                              context,
                              'Boy Persentili\nWHO',
                              persentilResult.whoHeightPercentile,
                              Colors.blue,
                              viewModel: viewModel,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // BKİ Persentili - Neyzi (Solda) ve WHO (Sağda) - FLIPPABLE
                      Row(
                        children: [
                          Expanded(
                            child: persentilResult.hasHeightAge
                                ? FlippableCard(
                                    frontChild: _buildDisplayBoxWithBorder(
                                      context,
                                      'BKİ Persentili\nNEYZİ (Kronolojik)',
                                      persentilResult.neyzieBmiPercentileChronoAge,
                                      Colors.orange,
                                      viewModel: viewModel,
                                    ),
                                    backChild: _buildDisplayBoxWithBorder(
                                      context,
                                      'BKİ Persentili\nNEYZİ (Boy Yaşı)',
                                      persentilResult.neyzieBmiPercentileHeightAge,
                                      Colors.orange,
                                      viewModel: viewModel,
                                      useHeightAgeForPercentiles: true,
                                    ),
                                  )
                                : _buildDisplayBoxWithBorder(
                                    context,
                                    'BKİ Persentili\nNEYZİ',
                                    persentilResult.neyzieBmiPercentileChronoAge,
                                    Colors.orange,
                                    viewModel: viewModel,
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: persentilResult.hasHeightAge
                                ? FlippableCard(
                                    frontChild: _buildDisplayBoxWithBorder(
                                      context,
                                      'BKİ Persentili\nWHO (Kronolojik)',
                                      persentilResult.whoBmiPercentileChronoAge,
                                      Colors.blue,
                                      viewModel: viewModel,
                                    ),
                                    backChild: _buildDisplayBoxWithBorder(
                                      context,
                                      'BKİ Persentili\nWHO (Boy Yaşı)',
                                      persentilResult.whoBmiPercentileHeightAge,
                                      Colors.blue,
                                      viewModel: viewModel,
                                      useHeightAgeForPercentiles: true,
                                    ),
                                  )
                                : _buildDisplayBoxWithBorder(
                                    context,
                                    'BKİ Persentili\nWHO',
                                    persentilResult.whoBmiPercentileChronoAge,
                                    Colors.blue,
                                    viewModel: viewModel,
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Boy Yaşı Durumu - Neyzi (Solda) ve WHO (Sağda) - NON-FLIPPABLE
                      Row(
                        children: [
                          Expanded(
                            child: _buildDisplayBoxWithBorder(
                              context,
                              'Boy Yaşı Durumu\nNEYZİ',
                              persentilResult.neyziHeightAgeStatus,
                              Colors.orange,
                              viewModel: viewModel,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildDisplayBoxWithBorder(
                              context,
                              'Boy Yaşı Durumu\nWHO',
                              persentilResult.whoHeightAgeStatus,
                              Colors.blue,
                              viewModel: viewModel,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const SizedBox(height: 10),
                    ],
                  );
                }
              ),
            ),

            // --- Hesaplamalar için Ağırlık Seç ---
            const Divider(height: 30),
            _buildSectionTitle(context, 'Hesaplamalar için Ağırlık Seç'),
            
            _buildWeightSourceCheckboxes(context, viewModel),
            
            if (viewModel.selectedWeightSource == WeightSource.manual)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: _buildTextField(
                  viewModel.calculationWeightController,
                  'Diyetisyen Tarafından Girilen Ağırlık (kg)',
                  inputType: TextInputType.number,
                ),
              ),
            
            if (showPercentileWeightDisplay) ...[
              const SizedBox(height: 10),
              _buildPercentileValueDropdown(context, viewModel),
              const SizedBox(height: 10),
              _buildDisplayField(
                viewModel.percentileWeightController,
                'Seçilen Persentil Ağırlığı (kg)',
                readOnly: true,
                isDense: false,
              ),
            ],
            
            const SizedBox(height: 10),
            _buildDisplayField(
              TextEditingController(text: viewModel.calculatedPercentiles.weightPercentile == '-' ? '' : viewModel.calculatedPercentiles.weightPercentile),
              'Mevcut Ağırlık Persentil Aralığı(Neyzi/WHO)',
              readOnly: true,
              isDense: false,
            ),

            // --- Günlük Gereksinimler ---
        const Divider(height: 30),
            _buildSectionTitle(context, 'Günlük Gereksinimler'),
             
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // SOL SÜTUN: HESAPLANAN GEREKSİNİMLER (Enerji, Protein, FA)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Enerji Gereksinimi:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.teal)),
                      const SizedBox(height: 6),
                      
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blue.shade300, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Checkbox(
                              value: viewModel.selectedEnergySources[EnergySource.doctor] ?? false,
                              onChanged: (value) {
                                viewModel.setSelectedEnergySource(EnergySource.doctor, value);
                                setState(() {
                                  viewModel.doctorEnergyCheckbox = value ?? false;
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildTextField(
                                viewModel.doctorEnergyController,
                                'Enerji (Doktor/Dyt. Hedefi)',
                                inputType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      _buildEnergyRequirementRow(
                          context, 
                          viewModel,
                          viewModel.energyReqController, 
                          'Enerji (PKU Referans Tablosu)', 
                          viewModel.enerjiReqTooltipString,
                          EnergySource.fku
                      ),
                      if (showEnerji2) 
                        _buildEnergyRequirementRow(
                            context, 
                            viewModel,
                            viewModel.energyReq2Controller, 
                            'Enerji (Pratik)', 
                            viewModel.enerjiReq2TooltipString,
                            EnergySource.practical
                        ),
                      if (showEnerji3)
                        _buildEnergyRequirementRow(
                            context, 
                            viewModel,
                            viewModel.energyReq3Controller, 
                            'Enerji (BMH*FAF+BGE)', 
                            viewModel.enerjiReq3TooltipString,
                            EnergySource.bmhFafBge
                        ),
                      
                      const SizedBox(height: 10),
                      const Text('Protein Gereksinimi:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.teal)),
                      const SizedBox(height: 6),
                      _buildTextField(
                        viewModel.doctorProteinController,
                        'Protein (Doktor/Dyt Hedefi)',
                        inputType: TextInputType.number,
                      ),
                      const SizedBox(height: 8),
                      // Hesaplanan Protein
                      _buildDisplayField( 
                        viewModel.proteinReqController, 
                        'Protein (g/kg)', 
                        tooltipMessage: viewModel.proteinReqTooltipString 
                      ),
                      
                      const SizedBox(height: 10),
                      const Text('Fenilalanin Gereksinimi:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.teal)),
                      const SizedBox(height: 6),
                      _buildTextField(
                        viewModel.doctorPheController,
                        'Fenilalanin (Doktor/Dyt Hedefi)',
                        inputType: TextInputType.number,
                      ),
                      const SizedBox(height: 8),
                      // Fenilalanin (sola yaslı)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _buildDisplayField( 
                          viewModel.pheReqController, 
                          'Fenilalanin (mg):', 
                          tooltipMessage: viewModel.pheReqTooltipString 
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // --- Hesaplamalar ve Referanslar (ExpansionTile ile gizle/goster) ---
            const Divider(height: 30),
            _buildCalculationAndReferencePanel(context, viewModel, showReferenceTable, showEnerji2, showEnerji3),

            // --- Besin Girişi ---
            const Divider(height: 30),
            _buildSectionTitle(context, 'Besin Değişim Tablosu'),
            // Manuel Başlık Satırı
            const Row(children: [
                Expanded(flex: 3, child: Text('Besin Adı', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Miktar', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Enerji(kcal)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Protein(g)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('FA(mg)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
            ],),
             const SizedBox(height: 5),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: viewModel.foodRows.length,
              itemBuilder: (context, index) {
                return _buildDraggableFoodInputRow(context, viewModel, index);
              },
            ),
            
            // --- Toplamlar ve Yüzdelikler (Görseldeki Gibi Dikey Hizalama) ---
            const Divider(height: 30),
            _buildSectionTitle(context, 'Toplamlar'),
            
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Sütun (Boş + TOPLAM etiketi)
                const Expanded(
                  flex: 5, // 3 (Besin Adı) + 2 (Miktar) = 5
                  child: Padding(
                    padding: EdgeInsets.only(top: 6.0),
                    child: Text('TOPLAM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), 
                  ),
                ),
                
                // 2. Sütun (ENERJİ)
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Toplam Değer
                      _buildDisplayField(viewModel.totalEnergyController, '', readOnly: true, isDense: true),
                      // Yüzdelik Bar
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: _buildPercentageBar(
                          context, 
                          viewModel.energyPercent, 
                          unit: 'kcal',
                          title: _getSelectedEnergySourceLabel(viewModel),
                          targetValue: _getSelectedEnergySourceTargetValue(viewModel),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                
                // 3. Sütun (PROTEİN)
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Toplam Değer
                      _buildDisplayField(viewModel.totalProteinController, '', readOnly: true, isDense: true),
                      // Yüzdelik Bar
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: _buildPercentageBar(context, viewModel.proteinPercent, unit: 'g', title: _getProteinLabel(viewModel)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                
                // 4. Sütun (FA)
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Toplam Değer
                      _buildDisplayField(viewModel.totalPheController, '', readOnly: true, isDense: true),
                      // Yüzdelik Bar
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: _buildPercentageBar(context, viewModel.phePercent, unit: 'mg', title: _getPheLabel(viewModel)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 15),
            // Görseldeki gibi barın hemen altındaki boşlukta yer alıyor
            Align( 
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text("Satır Ekle"),
                style: ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), textStyle: const TextStyle(fontSize: 14), ),
                onPressed: viewModel.addFoodRow,
              ),
            ),

            // --- Besinler ---
            const Divider(height: 30),
            _buildSectionTitle(context, 'Besinler'),
            Wrap( spacing: 8.0, runSpacing: 4.0, crossAxisAlignment: WrapCrossAlignment.center, children: [ ...viewModel.customFoods.map((food) { int index = viewModel.customFoods.indexOf(food); return _buildDraggableFoodItem( context, viewModel, DraggableFoodData( labelName: "custom_${food.name}", displayName: food.name, baseValues: BesinVerisi( fenilalaninDegeri: food.fa, proteinDegeri: food.protein, enerjiDegeri: food.enerji ), customFoodIndex: index, ), ); }), ], ),
            const SizedBox(height: 10),
            Row( children: [ 
              ElevatedButton.icon( 
                icon: const Icon(Icons.add, size: 18), 
                label: const Text("Yeni Besin Ekle"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => _showAddFoodDialog(context, viewModel, null), 
              ), 
              const SizedBox(width: 10), 
              ElevatedButton.icon( 
                icon: const Icon(Icons.edit, size: 18), 
                label: const Text("Besinleri Düzenle"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => _showEditFoodListDialog(context, viewModel), 
              ), 
            ], ),

            // --- Öğün Planı ---
            const Divider(height: 30),
            _buildSectionTitle(context, 'Öğün Planı'),
            // Sadece MealPlanOrder listesini kullaniyoruz.
            ...viewModel.mealPlanOrder.map((item) {
              if (item.isCustom) {
                final customMeal = item.reference as CustomMealSection;
                return _buildCustomMealSection(context, viewModel, customMeal);
              } else {
                final mealType = item.reference as MealType;
                return _buildMealSection(context, viewModel, mealType, item.name);
              }
            }).toList(),
            
            // Öğün Ekle Butonu
            const SizedBox(height: 10),
            Align( 
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add_box_outlined, size: 18),
                label: const Text("Özel Öğün Ekle"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 14),
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => _showInsertMealDialog(context, viewModel), 
              ),
            ),

            // --- Manuel PDF Aktarma Butonu ---
            const SizedBox(height: 25),
            Center( child: ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text("Manuel PDF Oluştur (İndirme Penceresi Açılır)"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                backgroundColor: Colors.blueGrey.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ), 
              onPressed: () async { 
                final scaffoldMessenger = ScaffoldMessenger.of(context); 
                scaffoldMessenger.showSnackBar( const SnackBar(content: Text('PDF dosyası oluşturuluyor... (İndirme penceresi bekleniyor)')), ); 
                String? result = await viewModel.exportToPdf(); 
                if (!context.mounted) return; 
                scaffoldMessenger.hideCurrentSnackBar(); 
                scaffoldMessenger.showSnackBar( SnackBar( 
                    content: Text(result ?? "Bilinmeyen bir hata oluştu."), 
                    backgroundColor: result != null && result.contains("başarıyla") ? Colors.green : (result?.contains("Uyarı:") == true || result?.contains("Hata:") == true ? Colors.orange : Colors.red), 
                    duration: const Duration(seconds: 5), 
                ), ); 
              }, 
            ), ),
            
            // --- Kaydetme/Güncelleme Butonları ---
            const Divider(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // YENİ TAKİP KAYDI EKLE (PDF'i kaydeder, açmaz ve dosya seçme diyaloğunu tetikler)
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: Text(isExistingRecord 
                    ? "Kaydet" 
                    : "Yeni Takip Kaydı Olarak Kaydet (JSON+PDF İndirme Penceresi)"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    backgroundColor: Colors.teal.shade800, 
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    // İlk kayıt oluşturulmuşsa, sonraki her değişiklik aynı dosyaya eklenir
                    final isFirstSave = viewModel.currentRecordId == null;
                    _handleSaveOrUpdate(isNewRecord: isFirstSave);
                  },
                ),
                
                // MEVCUT KAYDI GÜNCELLE
                if (isExistingRecord) ...[
                  const SizedBox(width: 15),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.update),
                    label: const Text("Mevcut Kaydı Güncelle"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Uyarı: Takip sistemi her zaman aynı hasta dosyasına takip kaydı ekler.'), backgroundColor: Colors.orange)
                      );
                      // isExistingRecord = true ise zaten recordId var, false yap
                      _handleSaveOrUpdate(isNewRecord: false); 
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
// YENİ METOT: Vizit Tarihi Seçici Widget'ı
Widget _buildVisitDatePickerField(BuildContext context, MetabolizmaViewModel viewModel) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: TextField(
          controller: viewModel.visitDateController,
          keyboardType: TextInputType.datetime,
          onChanged: (value) {
            // Boşsa temizle
            if (value.isEmpty) {
              if (viewModel.visitDate != null) viewModel.setVisitDate(null);
              return;
            }
            // Sadece tam GG.AA.YYYY uzunluğu geldiğinde parse etmeye çalış
            if (value.length != 10) return;
            try {
              final parsedDate = DateFormat('dd.MM.yyyy').parseStrict(value);
              if (viewModel.visitDate != parsedDate) viewModel.setVisitDate(parsedDate);
            } catch (_) {
              // Geçersiz format: yazmaya devam edilirken controller'ı temizleme
            }
          },
          style: const TextStyle(
            fontSize: 14.0, 
          ),
          inputFormatters: [
            _DateTextFormatter(), 
          ],
          readOnly: false, 
          decoration: InputDecoration(
            labelText: 'Vizit Tarihi (GG.AA.YYYY)',
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.blue.shade600, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Temizleme butonu
                IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () => viewModel.setVisitDate(null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Tarihi Temizle',
                ),
                // Takvim butonu
                IconButton(
                  icon: const Icon(Icons.calendar_today, size: 20),
                  onPressed: () async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: viewModel.visitDate ?? DateTime.now(),
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2100),
                      locale: const Locale('tr', 'TR'),
                    );
                    if (picked != null) viewModel.setVisitDate(picked);
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Takvimi Aç',
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      );
  }

// YENİ METOT: Vizit tarihi seçici diyalogunu açmak için

  Widget _buildSubHeader(BuildContext context, String title) { 
    if (title == '-') return const SizedBox.shrink();
    return Padding( 
      padding: const EdgeInsets.only(bottom: 12.0, top: 4.0), 
      child: Text(
        title, 
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: Colors.teal.shade700)
      ), 
    ); 
  }

  // YENİ WIDGET: Hesaplamalar ve Referanslar paneli
  Widget _buildCalculationAndReferencePanel(BuildContext context, MetabolizmaViewModel viewModel, bool showReferenceTable, bool showEnerji2, bool showEnerji3) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blue.shade300, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        initiallyExpanded: false, 
        tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
        title: Column( 
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hesaplamalar ve Referanslar',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Detayları görmek için tıklayınız', 
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                Expanded( 
                  flex: 5, 
                  child: Column( 
                    crossAxisAlignment: CrossAxisAlignment.start, 
                    children: [ 
                      _buildDisplayBox(context, 'BMH Hesabı:', viewModel.bmhCalculationString), 
                      _buildDisplayBox(context, 'BKİ Hesabı:', viewModel.bmiCalculationString), 
                      _buildDisplayBox(context, 'Enerji (PKU Referans Tablosu) Hesabı:', viewModel.enerjiReqCalculationString), 
                      if (showEnerji2) _buildDisplayBox(context, 'Enerji (Pratik) Hesabı:', viewModel.enerjiReq2CalculationString),
                      if (showEnerji3) _buildDisplayBox(context, 'Enerji (BMH*FAF+BGE) Hesabı:', viewModel.enerjiReq3CalculationString), 
                      _buildDisplayBox(context, 'Protein Ger. Hesabı:', viewModel.proteinReqCalculationString), 
                      _buildDisplayBox(context, 'FA Ger. Hesabı:', viewModel.pheReqCalculationString), 
                      
                      _buildCalculationRow('Protein Kısıt Kontrolü:', 
                                           viewModel.proteinReqTooltipString.contains("UYARI") ? "UYARI: Gereksinimden AZ" : "Uygun/KG Başına", 
                                           style: viewModel.proteinReqTooltipString.contains("UYARI") ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red) : null),
                    ], 
                  ), 
                ),
                const SizedBox(width: 20),
                Expanded( 
                  flex: 7, 
                  child: Visibility( 
                    visible: showReferenceTable,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                       const Text('PKU Referans Tablosu (Filtrelenmiş)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), 
                        _buildFilteredFKUReferenceTable(context, viewModel),
                        const SizedBox(height: 15),

                        const Text('Protein Katsayıları Tablosu (Filtrelenmiş)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 8),
                        _buildProteinReferenceTable(context, viewModel),
                      ],
                    ),
                  ), 
                ),
             ],
            ),
          ),
        ],
      ),
    );
  }

  // YENİ WIDGET: Hesaplama detaylarını kutucuk içinde göstermek için
  Widget _buildDisplayBox(BuildContext context, String label, String value) {
    if (value.trim() == "-") return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 2.0),
            child: Text(
              label, 
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8.0),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange.shade300, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value,
              style: TextStyle(fontFamily: 'monospace', color: Colors.grey[800], fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAgeNoteFromMonths(int months) {
    if (months < 12) {
      return "$months Ay";
    }
    final ageInYears = (months / 12.0).toStringAsFixed(1);
    return "$ageInYears Yıl ($months Ay)";
  }

  Widget _buildDisplayBoxWithBorder(
    BuildContext context,
    String label,
    String value,
    Color borderColor,
    {
      MetabolizmaViewModel? viewModel,
      bool useHeightAgeForPercentiles = false,
    }
  ) {
    // Grafik tipi belirleme
    String? chartType;
    if (label.contains('Ağırlık Persentili')) {
      chartType = label.contains('NEYZİ') ? 'neyzi_weight' : 'who_weight';
    } else if (label.contains('Boy Persentili')) {
      chartType = label.contains('NEYZİ') ? 'neyzi_height' : 'who_height';
    } else if (label.contains('BKİ Persentili')) {
      chartType = label.contains('NEYZİ') ? 'neyzi_bmi' : 'who_bmi';
    } else if (label.contains('Boy Yaşı Durumu')) {
      chartType = label.contains('NEYZİ') ? 'neyzi_height' : 'who_height';
    }
    
    // YAŞ BİLGİSİ NOTU OLUŞTUR
    String? ageNote;
    if (viewModel != null && label.contains('Boy Persentili')) {
      final bool isNeyziCard = label.contains('NEYZİ');
      final int heightAgeMonths = isNeyziCard
          ? viewModel.calculatedHeightAgeInMonths
          : viewModel.whoHeightAgeInMonths;
      if (heightAgeMonths > -1) {
        final displayAge = _formatAgeNoteFromMonths(heightAgeMonths);
        ageNote = "Boy Yaşına Göre ($displayAge)";
      }
    }
    
    // WHO BKİ için özel mesaj (2 yaştan küçükler için)
    if (value.trim() == "-" && label.contains('BKİ Persentili') && label.contains('WHO')) {
      return Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: borderColor.withOpacity(0.05),
          border: Border.all(color: borderColor, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: borderColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              '2 yaştan büyükler için hesaplanır',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    // WHO Ağırlık için özel mesaj (10 yaşından büyükler için)
    if (value.contains('10 yaşından büyük çocuklar')) {
      return Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: borderColor.withOpacity(0.05),
          border: Border.all(color: borderColor, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const Divider(height: 16),
            Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    if (value.trim() == "-") {
      return Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          border: Border.all(color: borderColor, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('Veri Yok', style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }
    
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: borderColor.withOpacity(0.05),
        border: Border.all(color: borderColor, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          // Ana içerik
          LayoutBuilder(
            builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 260;
          final labelText = Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: borderColor,
            ),
            textAlign: isNarrow ? TextAlign.left : TextAlign.center,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            maxLines: 3,
          );
          final iconWidget = chartType != null
              ? Tooltip(
                  message: 'Grafiği açmak için tıklayın',
                  waitDuration: const Duration(milliseconds: 200),
                  child: InkWell(
                    onTap: () {
                      final viewModel = context.read<MetabolizmaViewModel>();
                      final authService = context.read<AuthService>();
                      final currentUserData = authService.currentUser;
                      
                      // Mevcut hasta bilgilerinden PatientRecord oluştur
                      // Yaş hesaplama
                      int totalMonths = 0;
                      int years = 0;
                      int remainingMonths = 0;
                      
                      if (viewModel.dateOfBirth != null) {
                        final now = viewModel.visitDate ?? DateTime.now();
                        final birthDate = viewModel.dateOfBirth!;
                        
                        years = now.year - birthDate.year;
                        remainingMonths = now.month - birthDate.month;
                        
                        if (remainingMonths < 0) {
                          years--;
                          remainingMonths += 12;
                        }
                        
                        if (now.day < birthDate.day && remainingMonths > 0) {
                          remainingMonths--;
                        }
                        
                        totalMonths = (years * 12) + remainingMonths;
                      }
                    
                    final patientRecord = PatientRecord(
                      recordId: viewModel.currentRecordId,
                      ownerUserId: currentUserData?.userId ?? '',
                      patientName: viewModel.nameController.text.trim(),
                      recordDate: DateTime.now(),
                      recordDataJson: '{}',
                      weight: double.tryParse(viewModel.weightController.text) ?? 0,
                      height: double.tryParse(viewModel.heightController.text) ?? 0,
                      selectedGender: viewModel.selectedGender,
                      chronologicalAgeInMonths: totalMonths,
                      chronologicalAgeYears: years,
                      chronologicalAgeMonths: remainingMonths,
                      neyziWeightPercentile: viewModel.calculatedPercentiles.neyziWeightPercentile,
                      whoWeightPercentile: viewModel.calculatedPercentiles.whoWeightPercentile,
                      neyziHeightPercentile: viewModel.calculatedPercentiles.neyziHeightPercentile,
                      whoHeightPercentile: viewModel.calculatedPercentiles.whoHeightPercentile,
                      neyziBmiPercentile: viewModel.calculatedPercentiles.neyziBmiPercentile,
                      whoBmiPercentile: viewModel.calculatedPercentiles.whoBmiPercentile,
                      neyziHeightAgeStatus: viewModel.calculatedPercentiles.neyziHeightAgeStatus,
                      whoHeightAgeStatus: viewModel.calculatedPercentiles.whoHeightAgeStatus,
                    );
                    
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GrowthChartScreen(
                          patient: patientRecord,
                          initialChartType: chartType,
                        ),
                      ),
                    );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.black, width: 2),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.show_chart,
                        color: Colors.black,
                        size: 20,
                      ),
                    ),
                  ),
                )
              : null;

          Widget labelRow;
          if (isNarrow) {
            labelRow = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labelText,
                if (iconWidget != null) ...[
                  const SizedBox(height: 6),
                  Align(alignment: Alignment.centerLeft, child: iconWidget),
                ],
              ],
            );
          } else {
            labelRow = Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: labelText),
                if (iconWidget != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: iconWidget,
                  ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              labelRow,
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.grey[800],
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              _buildPercentileValues(context, viewModel, label, borderColor, value, useHeightAgeForPercentiles: useHeightAgeForPercentiles),
            ],
          );
        },
      ),
      // Yaş notu - Sol üst köşe (Responsive) - Sadece non-flippable kartlarda göster
      // Flippable kartlarda (label'da "Kronolojik" veya "Boy Yaşı" varsa) ageNote gösterme
      if (ageNote != null && !label.contains('Kronolojik') && !label.contains('Boy Yaşı'))
        Positioned(
          top: 0,
          left: 0,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Ekran genişliğine göre font boyutunu ayarla
              final screenWidth = MediaQuery.of(context).size.width;
              final double fontSize = screenWidth < 600 
                  ? 7.5  // Mobil için daha küçük
                  : screenWidth < 900 
                      ? 8.5  // Tablet için orta
                      : 9.5; // Desktop için normal
              
              return Container(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth < 600 ? 4 : 6,
                  vertical: screenWidth < 600 ? 2 : 3,
                ),
                decoration: BoxDecoration(
                  color: borderColor.withOpacity(0.15),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Text(
                  ageNote!,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: borderColor.withOpacity(0.9),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ),
      ],
    ),
    );
  }

  Widget _buildPercentileValues(
    BuildContext context,
    MetabolizmaViewModel? viewModel,
    String label,
    Color borderColor,
    String value, {
    bool useHeightAgeForPercentiles = false,
  }) {
    if (viewModel == null) {
      return const SizedBox.shrink();
    }

    String? dataType;
    String? source;

    if (label.contains('Ağırlık Persentili')) {
      dataType = 'weight';
      source = label.contains('NEYZİ') ? 'neyzi' : 'who';
    } else if (label.contains('Boy Persentili')) {
      dataType = 'height';
      source = label.contains('NEYZİ') ? 'neyzi' : 'who';
    } else if (label.contains('BKİ Persentili')) {
      dataType = 'bmi';
      source = label.contains('NEYZİ') ? 'neyzi' : 'who';
    } else if (label.contains('Boy Yaşı Durumu')) {
      if (!value.trim().startsWith('Boy Yaşı')) {
        return const SizedBox.shrink();
      }
      dataType = 'height';
      source = label.contains('NEYZİ') ? 'neyzi' : 'who';
    } else {
      return const SizedBox.shrink();
    }

    final gender = viewModel.selectedGender;
    if (gender.isEmpty) {
      return const SizedBox.shrink();
    }

    int chronologicalAgeInMonths = viewModel.currentAgeInMonths;
    final int? recordAgeInMonths = viewModel.currentRecord?.chronologicalAgeInMonths;
    if (chronologicalAgeInMonths <= 0 && (recordAgeInMonths ?? 0) > 0) {
      chronologicalAgeInMonths = recordAgeInMonths!;
    }

    if (chronologicalAgeInMonths <= 0 && viewModel.dateOfBirth != null) {
      final referenceDate = viewModel.visitDate ?? DateTime.now();
      final birthDate = viewModel.dateOfBirth!;
      int years = referenceDate.year - birthDate.year;
      int months = referenceDate.month - birthDate.month;
      if (months < 0) {
        years--;
        months += 12;
      }
      if (referenceDate.day < birthDate.day && months > 0) {
        months--;
      }
      chronologicalAgeInMonths = (years * 12) + months;
    }

    if (chronologicalAgeInMonths <= 0) {
      return const SizedBox.shrink();
    }

    int referenceAgeInMonths = chronologicalAgeInMonths;
    final bool isHeightAgeBox = label.contains('Boy Yaşı Durumu');
    final int? neyzHeightAge =
        viewModel.calculatedHeightAgeInMonths > -1 ? viewModel.calculatedHeightAgeInMonths : null;
    final int? whoHeightAge =
        viewModel.whoHeightAgeInMonths > -1 ? viewModel.whoHeightAgeInMonths : null;
    final int? candidateHeightAgeMonths = source == 'who' ? whoHeightAge : neyzHeightAge;

    if ((useHeightAgeForPercentiles || isHeightAgeBox) && candidateHeightAgeMonths != null) {
      referenceAgeInMonths = candidateHeightAgeMonths;
    }

    final String? ageLabel =
        referenceAgeInMonths > 0 ? _formatAgeForDisplay(referenceAgeInMonths) : null;

    return FutureBuilder<Map<String, double>>(
      future: _getPercentileValuesFromCSV(source, dataType, gender, referenceAgeInMonths),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final values = snapshot.data!;
        
        // Birimi belirle
        String unit = '';
        if (dataType == 'weight') {
          unit = 'kg';
        } else if (dataType == 'height') {
          unit = 'cm';
        } else if (dataType == 'bmi') {
          unit = 'kg/m²';
        }
        
        return Column(
          children: [
            if (value.isNotEmpty && value != '-') ...[
              const SizedBox(height: 8),
              // Topuz + İğne birlikte (Stack ile konumlandırılmış)
              _buildScalePointer(value),
              const SizedBox(height: 4),
            ],
            // Kantar skalası (persentil değerleri)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: borderColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                children: [
                  // Persentil etiketleri satırı (% ile başlayan)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: Text(
                          '%',
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.black54),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      _buildPercentileLabel('P3'),
                      _buildPercentileLabel('P10'),
                      _buildPercentileLabel('P25'),
                      _buildPercentileLabel('P50'),
                      _buildPercentileLabel('P75'),
                      _buildPercentileLabel('P90'),
                      _buildPercentileLabel('P97'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Persentil değerleri satırı (birim ile başlayan)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (ageLabel != null) ...[
                              Text(
                                ageLabel,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                            ],
                            Text(
                              unit,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      _buildPercentileValue(values['p3'] ?? 0),
                      _buildPercentileValue(values['p10'] ?? 0),
                      _buildPercentileValue(values['p25'] ?? 0),
                      _buildPercentileValue(values['p50'] ?? 0),
                      _buildPercentileValue(values['p75'] ?? 0),
                      _buildPercentileValue(values['p90'] ?? 0),
                      _buildPercentileValue(values['p97'] ?? 0),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPercentileLabel(String label) {
    return Expanded(
      child: Text(
        label,
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.black54),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildPercentileValue(double value) {
    return Expanded(
      child: Text(
        value > 0 ? value.toStringAsFixed(1) : '-',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildScalePointer(String value) {
    // Cetvel pozisyonları: [%, P3, P10, P25, P50, P75, P90, P97]
    // Pozisyon (0-1):      0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875
    
    double position = 0.5; // Varsayılan: ortada
    
    // P<3 veya P3'ün Altında - gösterge P3'ün solunda (% ile P3 arasında)
    if (value.contains('P<3') || value.contains('< P3') || 
        (value.contains('P3') && (value.contains('Altında') || value.contains('altında')))) {
      position = 0.0625; // % ile P3 arasının ortası (0 + 0.125) / 2
    } 
    // P>97 veya P97'nin Üzerinde - gösterge P97'nin sağında
    else if (value.contains('P>97') || value.contains('> P97') || 
             (value.contains('P97') && (value.contains('Üzerinde') || value.contains('üzerinde')))) {
      position = 0.9375; // P97'nin sağında (0.875 + 1.0) / 2
    } 
    // "P25-P50 Arası" gibi iki persentil arası durumlar
    else if (value.contains('P') && value.contains('Arası')) {
      final matches = RegExp(r'P(\d+)').allMatches(value).toList();
      if (matches.length >= 2) {
        final lower = int.parse(matches[0].group(1)!);
        final upper = int.parse(matches[1].group(1)!);
        
        // Cetvel üzerinde persentillerin pozisyonlarını bul
        final percentilePositions = {
          3: 0.125,
          10: 0.25,
          25: 0.375,
          50: 0.5,
          75: 0.625,
          90: 0.75,
          97: 0.875,
        };
        
        final lowerPos = percentilePositions[lower];
        final upperPos = percentilePositions[upper];
        
        if (lowerPos != null && upperPos != null) {
          position = (lowerPos + upperPos) / 2; // İki persentil arasının tam ortası
          print('DEBUG POINTER: "$value" -> lower=P$lower($lowerPos), upper=P$upper($upperPos), position=$position');
        }
      }
    }
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // Topuz ve iğnenin birlikte hareket etmesi için pozisyon hesapla
        final pointerLeft = constraints.maxWidth * (0.125 + position * 0.875);
        
        return Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: constraints.maxWidth,
              height: 40, // Topuz + iğne için yeterli alan
            ),
            // Topuz ve iğne birlikte konumlandırılmış
            Positioned(
              left: pointerLeft - 30, // Topuz merkezi için ayarlama (yaklaşık yarı genişlik)
              top: 0,
              child: SizedBox(
                width: 60, // Topuz genişliği
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Topuz (kantarın üst kısmı - persentil aralığı yazısı)
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 2),
                    // İğne (▼)
                    const Text(
                      '▼',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, double>> _getPercentileValuesFromCSV(String source, String dataType, String gender, int ageInMonths) async {
    print('DEBUG PERCENTILE BOX: source=$source, dataType=$dataType, gender=$gender, age=$ageInMonths');
    try {
      // Hardcode verilerden al
      List<dynamic> sourceData;
      
      if (source == 'who') {
        if (dataType == 'weight') {
          sourceData = gender == 'Erkek' ? PersentilData.whoErkekAgirlik : PersentilData.whoKadinAgirlik;
        } else if (dataType == 'height') {
          sourceData = gender == 'Erkek' ? PersentilData.whoErkekBoy : PersentilData.whoKadinBoy;
        } else {
          sourceData = gender == 'Erkek' ? PersentilData.whoErkekBmi : PersentilData.whoKadinBmi;
        }
      } else {
        if (dataType == 'weight') {
          sourceData = gender == 'Erkek' ? PersentilData.neyziErkekAgirlik : PersentilData.neyziKadinAgirlik;
        } else if (dataType == 'height') {
          sourceData = gender == 'Erkek' ? PersentilData.neyziErkekBoy : PersentilData.neyziKadinBoy;
        } else {
          sourceData = gender == 'Erkek' ? PersentilData.neyziErkekBmi : PersentilData.neyziKadinBmi;
        }
      }
      
      print('DEBUG PERCENTILE BOX: sourceData length = ${sourceData.length}');
      if (sourceData.isEmpty) return {};
      
      // Tam eşleşme var mı kontrol et
      for (final item in sourceData) {
        if (item.ageInMonths == ageInMonths) {
          final result = {
            'p3': item.percentile3 as double,
            'p10': item.percentile10 as double,
            'p25': item.percentile25 as double,
            'p50': item.percentile50 as double,
            'p75': item.percentile75 as double,
            'p90': item.percentile90 as double,
            'p97': item.percentile97 as double,
          };
          print('DEBUG PERCENTILE BOX: Exact match found at $ageInMonths months: $result');
          return result;
        }
      }
      
      // Tam eşleşme yok - en yakını bul
      int minDifference = 999999;
      dynamic closestData;
      int? closestAge;
      
      for (final item in sourceData) {
        final difference = (item.ageInMonths - ageInMonths).abs();
        
        if (difference < minDifference) {
          minDifference = difference;
          closestAge = item.ageInMonths;
          closestData = item;
        } else if (difference == minDifference && item.ageInMonths > ageInMonths) {
          // Eşit mesafedeyse üsttekini seç
          closestAge = item.ageInMonths;
          closestData = item;
        }
      }
      
      // En yakın yaşı kullan
      if (closestData != null) {
        print('DEBUG PERCENTILE BOX: Using closest age $closestAge for requested age $ageInMonths');
        return {
          'p3': closestData.percentile3 as double,
          'p10': closestData.percentile10 as double,
          'p25': closestData.percentile25 as double,
          'p50': closestData.percentile50 as double,
          'p75': closestData.percentile75 as double,
          'p90': closestData.percentile90 as double,
          'p97': closestData.percentile97 as double,
        };
      }
    } catch (e) {
      print('Error loading percentile values: $e');
    }
    return {};
  }

  String _formatAgeForDisplay(int totalMonths) {
    if (totalMonths <= 0) {
      return '0 Ay';
    }
    if (totalMonths < 12) {
      return '$totalMonths Ay';
    }

    final int years = totalMonths ~/ 12;
    final int months = totalMonths % 12;

    if (months == 0) {
      return '$years Yaş ($totalMonths Ay)';
    }

    return '$years Yaş $months Ay ($totalMonths Ay)';
  }

  // YENİ WIDGET: Enerji Gereksinimini Checkbox'li satir olarak olusturur
  Widget _buildEnergyRequirementRow(
    BuildContext context, 
    MetabolizmaViewModel viewModel,
    TextEditingController controller, 
    String label, 
    String? tooltipMessage,
    EnergySource source,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0), 
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.blue.shade300, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Checkbox
            SizedBox(
              width: 24,
              height: 52, 
              child: Center(
                child: Checkbox(
                  value: viewModel.selectedEnergySources[source] ?? false,
                  onChanged: (newValue) {
                    viewModel.setSelectedEnergySource(source, newValue);
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Display Field
            Expanded(
              child: _buildDisplayField(
                controller, 
                label, 
                readOnly: true, 
                isDense: false, 
                tooltipMessage: tooltipMessage
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // YENİ: Doğum Tarihi Seçici Widget
  Widget _buildDatePickerField(BuildContext context, MetabolizmaViewModel viewModel) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: TextField(
          controller: viewModel.dateOfBirthController,
          keyboardType: TextInputType.datetime,
          // ÖNEMLİ DÜZELTME: Doğum tarihi girildiğinde veya değiştirildiğinde hesaplamaları tetikle
          onChanged: (value) {
            if (value.isEmpty) {
              if (viewModel.dateOfBirth != null) viewModel.setDateOfBirth(null);
              return;
            }
            if (value.length != 10) return;
            try {
              final parsedDate = DateFormat('dd.MM.yyyy').parseStrict(value);
              if (viewModel.dateOfBirth != parsedDate) viewModel.setDateOfBirth(parsedDate);
            } catch (_) {
              // Geçersiz format - yazma devam ederken controller'ı temizleme
            }
          },
          style: const TextStyle(
            fontSize: 14.0, 
          ),
          inputFormatters: [
            _DateTextFormatter(), 
          ],
          readOnly: false, 
          decoration: InputDecoration(
            labelText: 'Doğum Tarihi (GG.AA.YYYY)',
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.blue.shade600, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Temizleme butonu
                IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () => viewModel.setDateOfBirth(null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Tarihi Temizle',
                ),
                const SizedBox(width: 4),
                // Takvim açma butonu
                IconButton(
                  icon: const Icon(Icons.calendar_month, size: 20),
                  onPressed: () => _showDatePickerDialog(context, viewModel),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Takvimi Aç',
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      );
  }

  // YENİ METOT: Tarih seçici diyalogunu açmak için
  void _showDatePickerDialog(BuildContext context, MetabolizmaViewModel viewModel) async {
      final DateTime? pickedDate = await showDatePicker(
              context: context,
              initialDate: viewModel.dateOfBirth ?? DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
              locale: const Locale('tr', 'TR'), 
              builder: (context, child) {
                  return Theme(
                      data: Theme.of(context).copyWith(
                          colorScheme: ColorScheme.light(
                              primary: Theme.of(context).primaryColor, 
                              onPrimary: Colors.white, 
                              onSurface: Colors.black, 
                          ),
                          textButtonTheme: TextButtonThemeData(
                              style: TextButton.styleFrom(
                                  foregroundColor: Theme.of(context).primaryColor, 
                              ),
                          ),
                      ),
                      child: child!,
                  );
              },
            );
            if (pickedDate != null) {
              viewModel.setDateOfBirth(pickedDate);
            }
  }
  
  // YENİ: Ağırlık Kaynağı Checkbox Grubu
  Widget _buildWeightSourceCheckboxes(BuildContext context, MetabolizmaViewModel viewModel) {
      void handleCheckboxChange(WeightSource source, bool? newValue) {
          viewModel.setWeightSource(newValue == true ? source : null);
      }
      
      final currentSource = viewModel.selectedWeightSource;
      
      return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              // SOL SÜTUN
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCheckboxTile(
                        context, 
                        "Kendi Ağırlığını Kullan", 
                        currentSource == WeightSource.current, 
                        (newValue) => handleCheckboxChange(WeightSource.current, newValue)
                    ),
                    const SizedBox(height: 10),
                    _buildCheckboxTile(
                        context, 
                        "WHO Persentilinden Ağırlık Kullan", 
                        currentSource == WeightSource.whoPercentile, 
                        (newValue) => handleCheckboxChange(WeightSource.whoPercentile, newValue)
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 15),
              // SAĞ SÜTUN
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCheckboxTile(
                        context, 
                        "Diyetisyenin Girdiği Ağırlığını Kullan", 
                        currentSource == WeightSource.manual, 
                        (newValue) => handleCheckboxChange(WeightSource.manual, newValue)
                    ),
                    const SizedBox(height: 10),
                    _buildCheckboxTile(
                        context, 
                        "Neyzi Persentilinden Ağırlık Kullan", 
                        currentSource == WeightSource.neyziPercentile, 
                        (newValue) => handleCheckboxChange(WeightSource.neyziPercentile, newValue)
                    ),
                  ],
                ),
              ),
          ],
      );
  }

  Widget _buildCheckboxTile(BuildContext context, String title, bool value, void Function(bool?) onChanged) { 
     return Container(
       decoration: BoxDecoration(
         border: Border.all(color: Colors.blue.shade300, width: 2),
         borderRadius: BorderRadius.circular(8),
       ),
       child: CheckboxListTile( 
         title: Text(title, style: const TextStyle(fontSize: 14)), 
         value: value, 
         onChanged: onChanged, 
         controlAffinity: ListTileControlAffinity.leading, 
         contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
         dense: true, 
         visualDensity: VisualDensity.compact, 
       ),
     );
  }

  // YENİ WIDGET: FKÜ Referans Tablosunu Filtreleyerek Gösterir (2 üst, 2 alt)
  Widget _buildFilteredFKUReferenceTable(BuildContext context, MetabolizmaViewModel viewModel) { 
    final headerStyle = Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 10); 
    final cellStyle = Theme.of(context).textTheme.labelMedium?.copyWith(fontSize: 10); 
    final highlightedCellStyle = Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.red.shade700, fontSize: 10); 
    
    // Yaş hesaplaması ViewModel içinden geliyor
    final (_, _, _, _) = _calculateAge(viewModel.dateOfBirth);

    final int highlightedIndex = viewModel.highlightedReferenceRowIndex;
    final allRows = viewModel.fkuReferenceRequirements;
    
    final int start = max(0, highlightedIndex - 2);
    final int end = min(allRows.length - 1, highlightedIndex + 2);

    final filteredRows = highlightedIndex != -1 
        ? allRows.sublist(start, end + 1)
        : allRows; 
    
    return SingleChildScrollView( 
      scrollDirection: Axis.horizontal, 
      child: DataTable( 
        columnSpacing: 10, 
        horizontalMargin: 8, 
        headingRowHeight: 50, 
        dataRowMinHeight: 30, 
        dataRowMaxHeight: 35, 
        border: TableBorder.all(color: Colors.grey.shade400, width: 1), 
        columns: [ 
          DataColumn(label: Text('Yaş', style: headerStyle)), 
          DataColumn(label: Text('FA\n(mg/kg) / (mg/gün)', style: headerStyle, textAlign: TextAlign.center)), 
          DataColumn(label: Text('Tirozin\n(mg/kg) / (g/gün)', style: headerStyle, textAlign: TextAlign.center)), 
          DataColumn(label: Text('Protein\n(g/kg) / (g/gün)', style: headerStyle, textAlign: TextAlign.center)), 
          DataColumn(label: Text('Enerji\n(kcal/kg) / (kcal/gün)', style: headerStyle, textAlign: TextAlign.center)), 
          DataColumn(label: Text('Sıvı\n(mL/kg) / (mL/gün)', style: headerStyle, textAlign: TextAlign.center)), 
        ], 
        rows: filteredRows.map((req) { 
          bool isHighlighted = req.index == highlightedIndex; 
          final currentCellStyle = isHighlighted ? highlightedCellStyle : cellStyle; 
          
          return DataRow( 
            color: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) { 
              return isHighlighted ? Colors.red.withOpacity(0.1) : null; 
            }), 
            cells: [ 
              DataCell(Text(req.ageGroup, style: currentCellStyle)), 
              DataCell(Text(req.pheRange, style: currentCellStyle, textAlign: TextAlign.center)), 
              DataCell(Text(req.tyrosineRange, style: currentCellStyle, textAlign: TextAlign.center)), 
              DataCell(Text(req.proteinRange, style: currentCellStyle, textAlign: TextAlign.center)), 
              DataCell(Text(req.energyRange, style: currentCellStyle, textAlign: TextAlign.center)), 
              DataCell(Text(req.fluidRange, style: currentCellStyle, textAlign: TextAlign.center)), 
            ], 
          ); 
        }).toList(), 
      ), 
    ); 
  }

  // YENİ WIDGET: Protein İhtiyacı Katsayı Tablosunu Gösterir (Filtrelenmiş ve Vurgulanmış)
  Widget _buildProteinReferenceTable(BuildContext context, MetabolizmaViewModel viewModel) { 
    final headerStyle = Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 10); 
    final cellStyle = Theme.of(context).textTheme.labelMedium?.copyWith(fontSize: 10); 
    final highlightedCellStyle = Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.blue.shade700, fontSize: 10); 
    
    // Vurgulama için kullanılacak yaş
    final referenceAgeInMonths = viewModel.calculatedHeightAgeInMonths != -1 
        ? viewModel.calculatedHeightAgeInMonths // Boy Yaşı Hesaplandıysa onu kullan
        : (_calculateAge(viewModel.dateOfBirth).$2); // Yoksa Kronolojik Ay kullan
    final ageInYears = referenceAgeInMonths ~/ 12;

    final int highlightedIndex = viewModel.getProteinTableHighlightedIndex(referenceAgeInMonths, ageInYears);
    final allRows = viewModel.proteinRequirementTable;
    
    final int start = max(0, highlightedIndex - 2);
    final int end = min(allRows.length - 1, highlightedIndex + 2);

    final filteredRows = highlightedIndex != -1 
        ? allRows.sublist(start, end + 1)
        : allRows;

    return SingleChildScrollView( 
      scrollDirection: Axis.horizontal, 
      child: DataTable( 
        columnSpacing: 15, 
        horizontalMargin: 8, 
        headingRowHeight: 50, 
        dataRowMinHeight: 30, 
        dataRowMaxHeight: 35, 
        border: TableBorder.all(color: Colors.grey.shade400, width: 1), 
        columns: [ 
          DataColumn(label: Text('Yaş Grubu', style: headerStyle)), 
          DataColumn(label: Text('Protein Katsayısı\n(g/kg/gün)', style: headerStyle, textAlign: TextAlign.center)), 
        ], 
        rows: filteredRows.map((data) { 
          final index = viewModel.proteinRequirementTable.indexOf(data);
          final isHighlighted = index == highlightedIndex;
          final currentCellStyle = isHighlighted ? highlightedCellStyle : cellStyle;

          final proteinValue = data.proteinKg.toStringAsFixed(1);
          
          return DataRow( 
            color: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) { 
              return isHighlighted ? Colors.blue.withOpacity(0.1) : null; 
            }), 
            cells: [ 
              DataCell(Text(data.ageGroup, style: currentCellStyle)), 
              DataCell(Text(proteinValue, style: currentCellStyle, textAlign: TextAlign.center)), 
            ], 
          ); 
        }).toList(), 
      ),
    ); 
  }
  
  // YARDIMCI: Yaş hesaplaması için (ViewModel'deki metot tekrarlandı, çünkü widget'lar build'de çağırıyor)
  (int years, int months, int days, double doubleAge) _calculateAge(DateTime? dateOfBirth) {
    if (dateOfBirth == null) return (0, 0, 0, 0.0);
    final now = DateTime.now();
    
    int years = now.year - dateOfBirth.year;
    int months = now.month - dateOfBirth.month;
    int days = now.day - dateOfBirth.day;

    if (days < 0) {
      months--;
      final lastMonth = DateTime(now.year, now.month, 0);
      days += lastMonth.day;
    }
    
    if (months < 0) {
      years--;
      months += 12;
    }

    if (years < 0) return (0, 0, 0, 0.0);

    final totalMonths = years * 12 + months;
    final doubleAge = totalMonths / 12.0;

    return (years, totalMonths, days, doubleAge);
  }

  
  Widget _buildSectionTitle(BuildContext context, String title) { 
    return Padding( 
      padding: const EdgeInsets.only(bottom: 8.0, top: 12.0), 
      child: Text(title, style: Theme.of(context).textTheme.titleLarge), 
    ); 
  }
  
  Widget _buildCalculationRow(String label, String calculation, {TextStyle? style}) { 
    if (calculation.trim() == "-" || calculation.trim().isEmpty) return const SizedBox.shrink(); 
    return Padding( 
      padding: const EdgeInsets.symmetric(vertical: 3.0), 
      child: Row( 
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [ 
          SizedBox( 
            width: 170, 
            child: Text(label, style: style ?? const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), 
          ), 
          Expanded( 
            child: Text( 
              calculation, 
              style: TextStyle(fontFamily: 'monospace', color: Colors.grey[800], fontSize: 12) 
            ), 
          ), 
        ], 
      ), 
    ); 
  }
  
  Widget _buildTextField(TextEditingController controller, String label, {TextInputType inputType = TextInputType.text, bool readOnly = false}) { 
    final bool isNumericInput = inputType == TextInputType.number; 
    final keyboardType = isNumericInput
        ? const TextInputType.numberWithOptions(decimal: true)
        : inputType;
    List<TextInputFormatter>? formatters; 
    if (isNumericInput) { 
      formatters = [FilteringTextInputFormatter.allow(RegExp(r'^\d*[,.]?\d*'))]; 
    } 
    return Padding( 
      padding: const EdgeInsets.symmetric(vertical: 6.0), 
      child: TextField( 
        controller: controller, 
        readOnly: readOnly, 
        keyboardType: keyboardType, 
        inputFormatters: formatters, 
        decoration: InputDecoration( 
          labelText: label, 
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue.shade600, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          isDense: true, 
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12), 
        ), 
      ), 
    ); 
  }
  
  Widget _buildDisplayField( TextEditingController controller, String label, { bool readOnly = true, bool isDense = false, String? tooltipMessage }) { 
    final textFieldWidget = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0), 
      child: TextField( 
        controller: controller, 
        readOnly: readOnly, 
        keyboardType: TextInputType.number, 
        textAlign: label.isEmpty ? TextAlign.right : TextAlign.left, 
        style: readOnly ? const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500) : null, 
        decoration: InputDecoration( 
          labelText: label.isEmpty ? null : label, 
          border: OutlineInputBorder(
            borderSide: BorderSide(color: readOnly ? Colors.orange.shade300 : Colors.blue.shade300, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: readOnly ? Colors.orange.shade300 : Colors.blue.shade300, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: readOnly ? Colors.orange.shade600 : Colors.blue.shade600, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          isDense: isDense, 
          filled: readOnly, 
          fillColor: readOnly ? Colors.grey[50] : null, 
          contentPadding: isDense ? const EdgeInsets.symmetric(horizontal: 8, vertical: 8) : const EdgeInsets.symmetric(horizontal: 10, vertical: 12), 
        ), // <-- TextField decoration kapatıldı
      ), // <-- Padding kapatıldı. Hata burada olabilir.
    );
    
    if (tooltipMessage != null && tooltipMessage.isNotEmpty && tooltipMessage != "-") { 
      return Tooltip( 
        message: tooltipMessage, 
        waitDuration: const Duration(milliseconds: 300), 
        padding: const EdgeInsets.all(8), 
        textStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500), 
        decoration: BoxDecoration( 
          color: Colors.black.withOpacity(0.85), 
          borderRadius: BorderRadius.circular(4), 
        ), 
        child: textFieldWidget, 
      ); 
    } 
    return textFieldWidget; 
  }
  
  Widget _buildSmallTextField(TextEditingController controller, TextInputType inputType, {bool readOnly = false}) {
    final keyboardType = inputType == TextInputType.number
        ? const TextInputType.numberWithOptions(decimal: true)
        : inputType;
    List<TextInputFormatter>? formatters;
    if (inputType == TextInputType.number) {
      formatters = [FilteringTextInputFormatter.allow(RegExp(r'^\d*[,.]?\d*'))];
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: keyboardType,
        inputFormatters: formatters,
        textAlign: TextAlign.right,
        style: readOnly ? const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500) : null,
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue.shade600, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
      ),
    );
  }

  Widget _buildDraggableFoodInputRow(BuildContext context, MetabolizmaViewModel viewModel, int index) {
     final rowState = viewModel.foodRows[index];
     bool isItemDropped = rowState.originalLabelName != null;
     double currentAmount = double.tryParse(rowState.amountController.text.replaceAll(',', '.')) ?? 0.0;
     bool canDrag = isItemDropped && currentAmount > 0;
     final format = NumberFormat("0.##", "tr_TR");

     final double opacity = currentAmount > 0.001 ? 1.0 : (isItemDropped ? 0.4 : 1.0); 
     
     Widget nameCell;
     if (isItemDropped) {
       nameCell = MouseRegion(
         cursor: canDrag ? SystemMouseCursors.grab : SystemMouseCursors.basic,
         child: Chip(
           label: Text(rowState.nameController.text),
           onDeleted: () => viewModel.satiriTemizle(index),
           backgroundColor: Colors.teal[50],
           deleteIconColor: Colors.red[700],
           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
           labelPadding: const EdgeInsets.only(left: 4),
           visualDensity: VisualDensity.compact,
           materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
         ),
       );
       nameCell = Padding(
         padding: const EdgeInsets.only(right: 5.0),
         child: InputDecorator( 
           decoration: InputDecoration(
             border: const OutlineInputBorder(),
             enabledBorder: OutlineInputBorder( borderSide: BorderSide( color: Colors.grey.shade400, width: 1, ), ),
             isDense: true,
             contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4), 
           ),
           child: ConstrainedBox(
             constraints: const BoxConstraints(minHeight: 28),
             child: Align(
               alignment: Alignment.centerLeft,
               child: nameCell, 
             ),
           ),
         ),
       );

     } else {
        nameCell = Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.only(right: 5.0),
            child: _buildSmallTextField(rowState.nameController, TextInputType.text), 
          ),
        );
     }
     
     Widget fullRowContent = Opacity(
        opacity: opacity, 
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isItemDropped) Expanded(flex: 3, child: nameCell) else nameCell, 
            Expanded(flex: 2, child: _buildSmallTextField(rowState.amountController, TextInputType.number)), const SizedBox(width: 5),
            Expanded(flex: 2, child: _buildSmallTextField(rowState.energyController, TextInputType.number, readOnly: true)), const SizedBox(width: 5),
            Expanded(flex: 2, child: _buildSmallTextField(rowState.proteinController, TextInputType.number, readOnly: true)), const SizedBox(width: 5),
            Expanded(flex: 2, child: _buildSmallTextField(rowState.pheController, TextInputType.number, readOnly: true)),
          ],
        ),
      );

     Widget rowWidget;
     if (isItemDropped) {
       rowWidget = Padding(
         padding: const EdgeInsets.symmetric(vertical: 1.0),
         child: Draggable<DraggableInputRowData>(
           data: DraggableInputRowData(sourceRowIndex: index, foodName: rowState.nameController.text, currentAmountText: rowState.amountController.text ),
           feedback: Material( elevation: 4.0, color: Colors.transparent, child: Container( padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Colors.lightGreen.withOpacity(0.8), borderRadius: BorderRadius.circular(4)), child: Text("${rowState.nameController.text} (${format.format(currentAmount)})", style: const TextStyle(color: Colors.white, fontSize: 14)), ), ),
           childWhenDragging: Opacity( opacity: 0.4, child: Padding(padding: const EdgeInsets.symmetric(vertical: 1.0), child: fullRowContent) ),
           onDragStarted: () => viewModel.handleDragStarted(),
           onDragUpdate: (details) => viewModel.handleDragUpdate(context, details),
           onDragEnd: (details) => viewModel.handleDragEnd(), 
           onDraggableCanceled: (velocity, offset) => viewModel.handleDragEnd(), 
           child: fullRowContent,
         ),
       );
     } else {
       rowWidget = Padding(
         padding: const EdgeInsets.symmetric(vertical: 1.0),
         child: DragTarget<DraggableFoodData>(
           builder: (context, candidateData, rejectedData) {
             return MouseRegion(
               cursor: SystemMouseCursors.click,
               child: Container(
                 padding: const EdgeInsets.symmetric(vertical: 0),
                 decoration: BoxDecoration( 
                   border: candidateData.isNotEmpty ? Border.all(color: Theme.of(context).primaryColor, width: 2) : Border.all(color: Colors.transparent, width: 2), 
                   borderRadius: BorderRadius.circular(4),
                   color: candidateData.isNotEmpty ? Theme.of(context).primaryColor.withOpacity(0.05) : null,
                 ),
                 child: fullRowContent, 
               ),
             );
           },
           onWillAcceptWithDetails: (details) => !isItemDropped,
           onAcceptWithDetails: (details) { viewModel.handleLabelDropOnFoodRow(context: context, data: details.data, targetRowIndex: index); }, 
         ),
       );
     }
     return rowWidget;
   }
   
  Widget _buildGenderDropdown(BuildContext context, MetabolizmaViewModel viewModel) { 
    return Padding( 
      padding: const EdgeInsets.symmetric(vertical: 6.0), 
      child: DropdownButtonFormField<String>( 
        value: viewModel.selectedGender, 
        decoration: InputDecoration( 
          labelText: 'Cinsiyet', 
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue.shade600, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          isDense: true, 
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12), 
        ), 
        items: ['Erkek', 'Kadın'] 
            .map((label) => DropdownMenuItem( 
                  value: label, 
                  child: Text(label), 
                )).toList(), 
        onChanged: (value) { 
          viewModel.setGender(value); 
        }, 
      ), 
    ); 
  }
   
  Widget _buildCheckbox(BuildContext context, String title, bool value, void Function(bool?) onChanged) { 
     return Container(
       decoration: BoxDecoration(
         border: Border.all(color: Colors.blue.shade300, width: 2),
         borderRadius: BorderRadius.circular(8),
       ),
       child: CheckboxListTile( 
         title: Text(title), 
         value: value, 
         onChanged: onChanged, 
         controlAffinity: ListTileControlAffinity.leading, 
         contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
         dense: true, 
         visualDensity: VisualDensity.compact, 
       ),
     );
  }

  // YENİ: Persentil Değeri Dropdown'ı
  Widget _buildPercentileValueDropdown(BuildContext context, MetabolizmaViewModel viewModel) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: DropdownButtonFormField<double>(
        value: viewModel.selectedPercentileValue,
        decoration: InputDecoration(
          labelText: 'Persentil Seçiniz',
          hintText: 'Önce yaş ve cinsiyet giriniz',
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue.shade600, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        ),
        items: viewModel.percentileOptions.map((value) {
          return DropdownMenuItem(
            value: value,
            child: Text('${value.toInt()}. Persentil'),
          );
        }).toList(),
        onChanged: viewModel.setPercentileValue,
      ),
    );
  }
  // YENİ WIDGET: Yüzdelik Barı oluşturur (En alta eklenmeli)
Widget _buildPercentageBar(BuildContext context, CalculatedPercentage data, {required String unit, String? title, double? targetValue}) {
    final statusStyle = data.color == Colors.red ? const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11)
        : data.color == const Color.fromARGB(255, 179, 190, 25)? const TextStyle(color: const Color.fromARGB(255, 179, 190, 25), fontWeight: FontWeight.bold, fontSize: 11)
        : const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11);
        
    final format = NumberFormat("0.##", "tr_TR");

    String targetText;
    if (targetValue != null && targetValue > 0) {
        // Seçilen enerji kaynağının hedefi (Enerji için kullanılan parametre)
        targetText = "Hedef: ${format.format(targetValue)} $unit";
    } else if (data.upperLimit > 0 && data.upperLimit != data.lowerLimit) {
        // Aralık gösterimi (Protein ve FA)
        targetText = "Hedef Aralığı: ${format.format(data.lowerLimit)} - ${format.format(data.upperLimit)} $unit";
    } else if (data.targetValue > 0) {
        // Tekil hedef gösterimi (Enerji)
        targetText = "Hedef: ${format.format(data.targetValue)} $unit";
    } else {
        targetText = "Hedef Belirlenmedi";
    }

   return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            // BAŞLIK YAZISI (Seçilen enerji kaynağı)
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                ),
              ),
            // DURUM VE YÜZDELİK ORANIN OLDUĞU SATIR
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                    // YÜZDELİK DEĞERİ
                    Text(
                        "${data.percentage.toStringAsFixed(1)}%", 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)
                    ),
                    
                    // DURUM METNİ (Hedef Karşılandı/Altında/Order vb.)
                    // YENİ EK: Esnekliği artırmak için metni Expanded içine alıp, taşma kontrolü ekliyoruz
                    Expanded(
                        child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                                data.status, 
                                style: statusStyle.copyWith(fontSize: 10), // Fontu küçülterek sığma şansını artır
                                softWrap: false, // İki satıra inmesini engelle (Tek satırda tutmaya çalışır)
                                overflow: TextOverflow.ellipsis, // Sığmazsa üç nokta koyar
                            ),
                        ),
                    ),
                ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: data.percentage / 100.0,
                    minHeight: 12,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(data.color),
                ),
            ),
            Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                    targetText,
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    softWrap: true, 
                    overflow: TextOverflow.ellipsis, 
                    maxLines: 2, 
                ),
            ),
        ],
    );
}
  Widget _buildDraggableFoodItem(BuildContext context, MetabolizmaViewModel viewModel, DraggableFoodData foodData) { 
    bool isVisible = viewModel.draggableLabelVisibility[foodData.labelName] ?? true; 
    
    if (!isVisible) {
      return Opacity( 
        opacity: 0.0, 
        child: Container( 
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: const Text("", style: TextStyle(color: Colors.transparent)),
        ),
      );
    }
    
    Widget labelContent = Container( 
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), 
      decoration: BoxDecoration( 
        color: Colors.grey[200], 
        border: Border.all(color: Colors.black54), 
        borderRadius: BorderRadius.circular(4), 
        boxShadow: [ BoxShadow( color: Colors.black.withOpacity(0.1), blurRadius: 2, offset: const Offset(1, 1), ) ] 
      ), 
      child: Text(foodData.displayName, style: const TextStyle(fontWeight: FontWeight.w500)), 
    ); 
    
    return Draggable<DraggableFoodData>( 
      data: foodData, 
      feedback: Material( elevation: 4.0, color: Colors.transparent, child: Container( padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration( color: Colors.blueAccent.withOpacity(0.8), borderRadius: BorderRadius.circular(4), ), child: Text(foodData.displayName, style: const TextStyle(color: Colors.white, fontSize: 14)), ), ), 
      childWhenDragging: Container( padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration( border: Border.all(color: Colors.grey[400]!), borderRadius: BorderRadius.circular(4), ), child: Text(foodData.displayName, style: TextStyle(color: Colors.grey[400])) ), 
      onDragStarted: () => viewModel.handleDragStarted(), 
      onDragUpdate: (details) => viewModel.handleDragUpdate(context, details),
      onDragEnd: (details) => viewModel.handleDragEnd(), 
      onDraggableCanceled: (velocity, offset) => viewModel.handleDragEnd(),
      child: MouseRegion( cursor: SystemMouseCursors.click, child: labelContent, ),
    );
  }

  void _showAddFoodDialog(BuildContext context, MetabolizmaViewModel viewModel, int? editIndex) { 
    final formKey = GlobalKey<FormState>(); 
    final CustomFood? existingFood = (editIndex != null && editIndex < viewModel.customFoods.length) ? viewModel.customFoods[editIndex] : null; 
    final bool isEditing = existingFood != null; 
    final bool canEditName = !isEditing || !existingFood.isDefault; 
    final nameController = TextEditingController(text: existingFood?.name ?? ""); 
    final proteinController = TextEditingController(text: existingFood != null ? _formatDouble(existingFood.protein) : ""); 
    final faController = TextEditingController(text: existingFood != null ? _formatDouble(existingFood.fa) : ""); 
    final enerjiController = TextEditingController(text: existingFood != null ? _formatDouble(existingFood.enerji) : ""); 
    final decimalFormatter = FilteringTextInputFormatter.allow(RegExp(r'^\d*[,.]?\d*')); 
    
    showDialog( 
      context: context, 
      barrierDismissible: false, 
      builder: (BuildContext dialogContext) { 
        return AlertDialog( 
          title: Text(isEditing ? 'Besini Düzenle' : 'Yeni Sürüklenebilir Besin Ekle'), 
          content: Form( 
            key: formKey, 
            child: SingleChildScrollView( 
              child: Column( 
                mainAxisSize: MainAxisSize.min, 
                children: <Widget>[ 
                  TextFormField( 
                    controller: nameController, 
                    readOnly: !canEditName, 
                    decoration: InputDecoration( 
                      labelText: 'Besin Adı', 
                      filled: !canEditName, 
                      fillColor: !canEditName ? Colors.grey[200] : null, 
                    ), 
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Besin adı boş olamaz' : null, 
                  ), 
                  const SizedBox(height: 8), 
                  TextFormField( 
                    controller: proteinController, 
                    decoration: const InputDecoration(labelText: 'Protein (g)'), 
                    keyboardType: const TextInputType.numberWithOptions(decimal: true), 
                    inputFormatters: [decimalFormatter], 
                    validator: (value) => _validateDecimal(value, 'Protein'), 
                  ), 
                  const SizedBox(height: 8), 
                  TextFormField( 
                    controller: faController, 
                    decoration: const InputDecoration(labelText: 'Fenilalanin (mg)'), 
                    keyboardType: const TextInputType.numberWithOptions(decimal: true), 
                    inputFormatters: [decimalFormatter], 
                    validator: (value) => _validateDecimal(value, 'FA'), 
                  ), 
                  const SizedBox(height: 8), 
                  TextFormField( 
                    controller: enerjiController, 
                    decoration: const InputDecoration(labelText: 'Enerji (kcal)'), 
                    keyboardType: const TextInputType.numberWithOptions(decimal: true), 
                    inputFormatters: [decimalFormatter], 
                    validator: (value) => _validateDecimal(value, 'Enerji'), 
                  ), 
                ], 
              ), 
            ), 
          ), 
          actions: <Widget>[ 
            TextButton( 
              child: const Text('İptal'), 
              onPressed: () => Navigator.of(dialogContext).pop(), 
            ), 
            ElevatedButton( 
              child: const Text('Kaydet'), 
              onPressed: () async { 
                if (formKey.currentState!.validate()) { 
                  try { 
                    final proteinValue = double.parse(proteinController.text.replaceAll(',', '.')); 
                    final faValue = double.parse(faController.text.replaceAll(',', '.')); 
                    final enerjiValue = double.parse(enerjiController.text.replaceAll(',', '.')); 
                    
                    if (isEditing) { 
                      await viewModel.updateCustomFood( 
                        index: editIndex!, 
                        name: nameController.text.trim(), 
                        protein: proteinValue, 
                        fa: faValue, 
                        enerji: enerjiValue, 
                      ); 
                    } else { 
                      await viewModel.addNewCustomFood( 
                        name: nameController.text.trim(), 
                        protein: proteinValue, 
                        fa: faValue, 
                        enerji: enerjiValue, 
                      ); 
                    } 
                    Navigator.of(dialogContext).pop(); 
                  } catch (e) { 
                    ScaffoldMessenger.of(context).showSnackBar( 
                      SnackBar(content: Text('Hata: ${e.toString().replaceFirst("Exception: ", "")}'), backgroundColor: Colors.red) 
                    ); 
                  } 
                } 
              }, 
            ), 
          ], 
        ); 
      }, 
    ); 
  }
  
  void _showEditFoodListDialog(BuildContext context, MetabolizmaViewModel viewModel) { 
    showDialog( 
      context: context, 
      builder: (BuildContext dialogContext) { 
        return ChangeNotifierProvider.value( 
          value: viewModel, 
          child: AlertDialog( 
            title: const Text('Besin Listesini Düzenle'), 
            content: Container( 
              width: double.maxFinite, 
              child: Consumer<MetabolizmaViewModel>( 
                builder: (context, vm, child) { 
                  if (vm.customFoods.isEmpty) { 
                    return const Center(child: Text('Kayıtlı besin bulunamadı.')); 
                  } 
                  return ListView.builder( 
                    shrinkWrap: true, 
                    itemCount: vm.customFoods.length, 
                    itemBuilder: (context, index) { 
                      final food = vm.customFoods[index]; 
                      return ListTile( 
                        title: Text(food.name), 
                        subtitle: Text('P: ${_formatDouble(food.protein)}, FA: ${_formatDouble(food.fa)}, E: ${_formatDouble(food.enerji)}'), 
                        trailing: Row( 
                          mainAxisSize: MainAxisSize.min, 
                          children: [ 
                            IconButton( 
                              icon: const Icon(Icons.edit, color: Colors.blue), 
                              onPressed: () { 
                                Navigator.of(dialogContext).pop(); 
                                _showAddFoodDialog(context, viewModel, index); 
                              }, 
                            ), 
                            if (!food.isDefault) 
                              IconButton( 
                                icon: const Icon(Icons.delete, color: Colors.red), 
                                onPressed: () async { 
                                  final bool? confirmed = await showDialog<bool>( 
                                    context: context, 
                                    builder: (confirmCtx) => AlertDialog( 
                                      title: const Text('Besini Sil?'), 
                                      content: Text('"${food.name}" adlı besini kalıcı olarak silmek istediğinizden emin misiniz?'), 
                                      actions: [ 
                                        TextButton(onPressed: () => Navigator.of(confirmCtx).pop(false), child: const Text('İptal')), 
                                        TextButton(onPressed: () => Navigator.of(confirmCtx).pop(true), child: const Text('Sil', style: TextStyle(color: Colors.red))), 
                                      ], 
                                    ), 
                                  ); 
                                  if (confirmed == true && context.mounted) { 
                                    try { 
                                      await vm.deleteCustomFood(index); 
                                    } catch (e) { 
                                      ScaffoldMessenger.of(context).showSnackBar( 
                                        SnackBar(content: Text('Hata: ${e.toString().replaceFirst("Exception: ", "")}'), backgroundColor: Colors.red) 
                                      ); 
                                    } 
                                  } 
                                }, 
                              ), 
                          ], 
                        ), 
                      ); 
                    }, 
                  ); 
                }, 
              ), 
            ), 
            actions: [ 
              TextButton( 
                child: const Text('Kapat'), 
                onPressed: () => Navigator.of(dialogContext).pop(), 
              ), 
            ], 
          ), 
        ); 
      }, 
    ); 
  }
  
  String? _validateDecimal(String? value, String fieldName) { 
    if (value == null || value.isEmpty) return '$fieldName boş olamaz'; 
    final val = double.tryParse(value.replaceAll(',', '.')); 
    if (val == null || val < 0) return 'Geçerli bir sayı girin (>= 0)'; 
    return null; 
  }
  
  String _formatDouble(double value) { 
    final format = NumberFormat("0.##", "tr_TR"); 
    return format.format(value); 
  }
  
  Widget _buildMealSection(BuildContext context, MetabolizmaViewModel viewModel, MealType mealType, String title) { 
    final entries = context.select((MetabolizmaViewModel vm) => vm.mealEntries[mealType] ?? []); 
    
    return Padding( 
      padding: const EdgeInsets.symmetric(vertical: 6.0), 
      child: DragTarget<DraggableInputRowData>( 
        builder: (context, candidateData, rejectedData) { 
          return InputDecorator( 
            decoration: InputDecoration( 
              labelText: title, 
              border: const OutlineInputBorder(), 
              enabledBorder: OutlineInputBorder( 
                borderSide: BorderSide( 
                  color: candidateData.isNotEmpty ? Colors.lightGreen : Colors.grey, 
                  width: candidateData.isNotEmpty ? 2 : 1, 
                ), 
              ), 
            ), 
            child: ConstrainedBox( 
              constraints: const BoxConstraints(minHeight: 48), 
              child: entries.isEmpty ? Center(child: Text('Buraya sürükleyin', style: TextStyle(color: Colors.grey[600]))) : Wrap( 
                spacing: 6.0, 
                runSpacing: 4.0, 
                children: List<Widget>.generate(entries.length, (index) { 
                  final entry = entries[index]; 
                  return Chip( 
                    label: Text(entry.toString()), 
                    backgroundColor: Colors.teal[50], 
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, 
                    onDeleted: () { 
                      viewModel.removeFoodFromMeal(meal: mealType, entryIndex: index); 
                    }, 
                    deleteIconColor: Colors.red[700], 
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), 
                  ); 
                }), 
              ), 
            ), 
          ); 
        }, 
        onWillAcceptWithDetails: (details) => true,
        onAcceptWithDetails: (details) { 
          viewModel.assignFoodToMeal( 
            context: context, 
            sourceRowIndex: details.data.sourceRowIndex, 
            targetMeal: mealType, 
          ); 
        }, 
      ), 
    ); 
  }
  
  Widget _buildCustomMealSection(BuildContext context, MetabolizmaViewModel viewModel, CustomMealSection customMeal) { 
    final entries = customMeal.entries; 
    
    return Padding( 
      padding: const EdgeInsets.symmetric(vertical: 6.0), 
      child: DragTarget<DraggableInputRowData>( 
        builder: (context, candidateData, rejectedData) { 
          return InputDecorator( 
            decoration: InputDecoration( 
              labelText: customMeal.name, 
              border: const OutlineInputBorder(), 
              enabledBorder: OutlineInputBorder( 
                borderSide: BorderSide( 
                  color: candidateData.isNotEmpty ? Colors.lightGreen : Colors.grey, 
                  width: candidateData.isNotEmpty ? 2 : 1, 
                ), 
              ), 
            ), 
            child: ConstrainedBox( 
              constraints: const BoxConstraints(minHeight: 48), 
              child: entries.isEmpty ? Center(child: Text('Buraya sürükleyin', style: TextStyle(color: Colors.grey[600]))) : Wrap( 
                spacing: 6.0, 
                runSpacing: 4.0, 
                children: List<Widget>.generate(entries.length, (index) { 
                  final entry = entries[index]; 
                  return Chip( 
                    label: Text(entry.toString()), 
                    backgroundColor: Colors.lightBlue[50], 
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, 
                    onDeleted: () { 
                      viewModel.removeFoodFromCustomMeal(customMeal: customMeal, entryIndex: index); 
                    }, 
                    deleteIconColor: Colors.red[700], 
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), 
                  ); 
                }), 
              ), 
            ), 
          ); 
        }, 
        onWillAcceptWithDetails: (details) => true,
        onAcceptWithDetails: (details) { 
          viewModel.assignFoodToCustomMeal( 
            context: context, 
            sourceRowIndex: details.data.sourceRowIndex, 
            targetCustomMeal: customMeal,
          );
        },
      ),
    ); 
  }
  
  void _showInsertMealDialog(BuildContext context, MetabolizmaViewModel viewModel) {
    final mealNameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final List<MealPlanItem> mealOrder = viewModel.mealPlanOrder;
    
    final List<({int index, String display})> insertionPoints = [];

    insertionPoints.add((index: 0, display: "En Başa (Sabah Öncesi)"));

    for (int i = 0; i < mealOrder.length; i++) {
        final meal = mealOrder[i];
        int insertionIndex = i + 1;
        insertionPoints.add((index: insertionIndex, display: "'${meal.name}' Sonrasına"));
    }
    
    ({int index, String display}) selectedInsertionPoint = insertionPoints.last;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (stfContext, stfSetState) {
            return AlertDialog(
              title: const Text('Yeni Özel Öğün Ekle'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextFormField(
                        controller: mealNameController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Öğün Adı',
                          hintText: 'Örn: Ara Öğün 1',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Lütfen bir öğün adı girin.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 15),
                      const Text('Eklenecek Pozisyon:', style: TextStyle(fontWeight: FontWeight.bold)),
                      DropdownButtonFormField<({int index, String display})>(
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          border: OutlineInputBorder(),
                        ),
                        value: selectedInsertionPoint,
                        items: insertionPoints.map((point) {
                          return DropdownMenuItem<({int index, String display})>(
                            value: point,
                            child: Text(point.display, style: const TextStyle(fontSize: 14)),
                          );
                        }).toList(),
                        onChanged: (value) {
                          stfSetState(() {
                            selectedInsertionPoint = value!;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('İptal'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                ElevatedButton(
                  child: const Text('Ekle'),
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      viewModel.addCustomMeal(
                        mealNameController.text,
                        selectedInsertionPoint.index, 
                      );
                      Navigator.of(dialogContext).pop();
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Helper: Seçilen enerji kaynağının etiketini döndür
  String _getSelectedEnergySourceLabel(MetabolizmaViewModel viewModel) {
    if (viewModel.selectedEnergySources[EnergySource.doctor] == true) {
      return '% Enerji (Doktor/Dyt. Hedefi)';
    } else if (viewModel.selectedEnergySources[EnergySource.practical] == true) {
      return '% Enerji (Pratik)';
    } else if (viewModel.selectedEnergySources[EnergySource.bmhFafBge] == true) {
      return '% Enerji (BMH*FAF+BGE)';
    } else {
      return '% Enerji (PKU Referans Tablosu)';
    }
  }

  // Helper: Seçilen enerji kaynağının hedef değerini döndür
  double _getSelectedEnergySourceTargetValue(MetabolizmaViewModel viewModel) {
    if (viewModel.selectedEnergySources[EnergySource.doctor] == true) {
      return double.tryParse(viewModel.doctorEnergyController.text.replaceAll(',', '.')) ?? 0.0;
    } else if (viewModel.selectedEnergySources[EnergySource.practical] == true) {
      return double.tryParse(viewModel.energyReq2Controller.text.replaceAll(',', '.')) ?? 0.0;
    } else if (viewModel.selectedEnergySources[EnergySource.bmhFafBge] == true) {
      return double.tryParse(viewModel.energyReq3Controller.text.replaceAll(',', '.')) ?? 0.0;
    } else {
      return double.tryParse(viewModel.energyReqController.text.replaceAll(',', '.')) ?? 0.0;
    }
  }

  // Helper: Protein etiketini döndür (Doktor hedefi girilmişse vs hesaplanan)
  String _getProteinLabel(MetabolizmaViewModel viewModel) {
    final doctorProteinText = viewModel.doctorProteinController.text.trim();
    if (doctorProteinText.isNotEmpty && double.tryParse(doctorProteinText.replaceAll(',', '.')) != null) {
      return '% Protein (Doktor/Dyt. Hedefi)';
    } else {
      return '% Protein (Hesaplanan)';
    }
  }

  // Helper: Fenilalanin etiketini döndür (Doktor hedefi girilmişse vs hesaplanan)
  String _getPheLabel(MetabolizmaViewModel viewModel) {
    final doctorPheText = viewModel.doctorPheController.text.trim();
    if (doctorPheText.isNotEmpty && double.tryParse(doctorPheText.replaceAll(',', '.')) != null) {
      return '% Fenilalanin (Doktor/Dyt. Hedefi)';
    } else {
      return '% Fenilalanin (Hesaplanan)';
    }
  }
}

// YENİ SINIF: Otomatik tarih formatlama için
class _DateTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
    ) {
    final String raw = newValue.text;
    final String cleanText = raw.replaceAll(RegExp(r'[^\d]'), '');

    // Yeni metni oluştur (GG.AA.YYYY)
    String newText = '';
    for (int i = 0; i < cleanText.length && i < 8; i++) {
      newText += cleanText[i];
      if (i == 1 || i == 3) {
        if (i + 1 != cleanText.length) newText += '.';
      }
    }

    // Sınırla
    if (newText.length > 10) newText = newText.substring(0, 10);

    int newCursorPosition;

    if (oldValue.text.length > newValue.text.length) {
      // Silme işlemi: mümkün olan yerde yeni selection'ı koru (ve sınırla)
      newCursorPosition = newValue.selection.end;
      if (newCursorPosition > newText.length) newCursorPosition = newText.length;
    } else {
      // Ekleme/ilerleme: genellikle imleci metnin sonuna koy
      newCursorPosition = newValue.selection.end;
      // Nokta eklenmesi nedeniyle sıçrama gerekiyorsa ayarla
      if (newCursorPosition == 3 && cleanText.length > 2) newCursorPosition++;
      if (newCursorPosition == 6 && cleanText.length > 4) newCursorPosition++;
      if (newCursorPosition > newText.length) newCursorPosition = newText.length;
      // Eğer selection 0 ise (bazı platformlarda) ve metin var ise son konuma al
      if (newCursorPosition == 0 && newText.isNotEmpty) newCursorPosition = newText.length;
    }

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPosition),
    );
  }
}