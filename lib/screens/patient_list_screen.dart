// lib/screens/patient_list_screen.dart
import 'fa_graph_screen.dart';
import 'tyrosine_graph_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/patient_service.dart'; 
import '../models/models.dart'; 
import 'login_screen.dart'; 
import 'metabolizma_screen.dart';
import 'growth_chart_screen.dart';
import 'growth_assessment_screen.dart';

class PatientListScreen extends StatefulWidget { 
  const PatientListScreen({super.key});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  final PatientService _patientService = PatientService();
  
  @override
  void initState() {
    super.initState();
    // PatientService'i initialize et
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authService = Provider.of<AuthService>(context, listen: false);
      _patientService.init(authService);
    });
  }
  
  void _navigateToMetabolizma(BuildContext context, {PatientRecord? record}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MetabolizmaScreen(
          initialRecord: record, 
        ),
      ),
    ).then((_) {
      // SharedPreferences'tan veri yüklemek için listeyi yeniden çek
      setState(() {}); 
    }); 
  }

  // GÜNCELLENDİ: PDF yolu web'de sadece referans/indirme için kullanılacak
  void _openPdfFile(BuildContext context, String? path) async {
      // PDF'in harici kaydı FileSaver ile yapıldığı için burada sadece uyarı veriyoruz
      // veya kullanıcıya kaydettiği konumu hatırlatıyoruz.
      // Web'de OpenFilex, indirme sonrası dosyayı tarayıcıda açmaya çalışır (genellikle indirme başarılı olur).
      if (path != null && path.isNotEmpty && !path.contains("HATA") && !path.contains("İptal Edildi")) {
        // Aslında bu path, FileSaver tarafından döndürülen gerçek indirme yolu (varsa) veya bir mesaj.
        // Web'de bu tam olarak işe yaramayabilir, sadece kullanıcıyı bilgilendiririz.
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("PDF, kayıt sırasında indirme penceresi aracılığıyla cihazınıza kaydedildi. Kaydettiğiniz konumu kontrol edin. Kayıt yolu bilgisi: $path"), duration: const Duration(seconds: 5), backgroundColor: Colors.blue),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu takip kaydı için harici PDF kaydı bulunamadı veya iptal edildi.'), backgroundColor: Colors.orange),
        );
      }
  }
  
  // YENİ METOT: Hastanın tüm kayıtlarını silmek için onay diyaloğu
  Future<void> _confirmDeletePatient(BuildContext context, String patientName) async {
    final patientService = Provider.of<PatientService>(context, listen: false);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Tüm Hasta Kayıtlarını Sil'),
          content: Text('"${patientName}" adlı hastanın TİM takip kayıtlarını kalıcı olarak silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.'),
          actions: <Widget>[
            TextButton(
              child: const Text('İptal'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Sil', style: TextStyle(color: Colors.white)),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await patientService.deleteAllRecordsByPatientName(patientName);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${patientName}" adlı hastanın tüm kayıtları silindi.'), backgroundColor: Colors.green),
          );
          // Listeyi yeniden yükle
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Silme hatası: ${e.toString()}'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final patientService = Provider.of<PatientService>(context);
    final currentUser = authService.currentUser;
    
    if (currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    final patientsFuture = patientService.getRecordsByUserId(currentUser.userId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hastalarım'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Çıkış Yap',
            onPressed: () {
              authService.signOut();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (Route<dynamic> route) => false, 
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<List<PatientRecord>>( 
        future: patientsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Veri yüklenirken hata oluştu: ${snapshot.error}'));
          }
          
          final patientRecords = snapshot.data ?? [];
          
          if (patientRecords.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Hoş Geldiniz, ${currentUser.username}!',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Henüz kayıtlı hasta bulunmamaktadır. Yeni bir hesaplama başlatın.',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Yeni Hasta Dosyası Ekle'),
                    onPressed: () => _navigateToMetabolizma(context), 
                  ),
                ],
              ),
            );
          }
          
          final latestRecords = <String, PatientRecord>{};
          for (var record in patientRecords) {
              if (!latestRecords.containsKey(record.patientName) || record.recordDate.isAfter(latestRecords[record.patientName]!.recordDate)) {
                  latestRecords[record.patientName] = record;
              }
          }

          final patientNames = latestRecords.keys.toList()..sort();


          return ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: patientNames.length,
              itemBuilder: (context, index) {
                final patientName = patientNames[index];
                final latestRecord = latestRecords[patientName]!;
                
                // PDF yolu artık harici kaydetme başarısını/yolunu tutuyor
                final bool hasPdf = latestRecord.pdfFilePath != null && latestRecord.pdfFilePath!.isNotEmpty && !latestRecord.pdfFilePath!.contains("HATA") && !latestRecord.pdfFilePath!.contains("İptal Edildi");
                
                // Cinsiyet bazlı renk
                final isMale = latestRecord.selectedGender.toLowerCase() == 'erkek';
                final cardColor = isMale ? Colors.blue.shade50 : Colors.pink.shade50;
                final iconColor = isMale ? Colors.blue : Colors.pink;

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  color: cardColor, 
                  
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.person, 
                          color: iconColor,
                          size: 32,
                        ),
                        title: Text(patientName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          'Cinsiyet: ${latestRecord.selectedGender} • Son Takip: ${DateFormat('dd.MM.yyyy HH:mm').format(latestRecord.recordDate)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () {
                          _navigateToMetabolizma(context, record: latestRecord);
                        },
                        // SİLME İKONU VE İŞLEVİ EKLENDİ
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_forever, color: Colors.red, size: 24),
                          tooltip: 'Bu hastanın TÜM kayıtlarını sil',
                          onPressed: () => _confirmDeletePatient(context, patientName),
                        ),
                      ),
                      
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Wrap(
                          spacing: 8.0,
                          runSpacing: 8.0,
                          alignment: WrapAlignment.start,
                          children: [
                            // Yeni Buton 1: PDF Raporunu Aç
                            Tooltip(
                              message: hasPdf ? 'PDF Raporunu Aç (Kaydedilen konumu kontrol edin)' : 'PDF Raporu Bulunamadı (Kayıt sırasında iptal edilmiş olabilir)',
                              child: ElevatedButton.icon(
                                onPressed: hasPdf ? () => _openPdfFile(context, latestRecord.pdfFilePath) : null,
                                icon: const Icon(Icons.picture_as_pdf, size: 18),
                                label: const Text('PDF Aç'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: hasPdf ? Colors.red.shade700 : Colors.grey.shade400,
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                              ),
                            ),

                            // Yeni Buton 2: Persentil Grafiği/Tabloları Aç
                            Tooltip(
                              message: 'Büyüme Grafiğini ve Persentil Tablolarını Aç',
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  // En güncel kaydı yeniden çek
                                  final records = await _patientService.getAllPatientRecords(patientName);
                                  if (records.isEmpty) return;
                                  
                                  records.sort((a, b) => b.recordDate.compareTo(a.recordDate));
                                  final freshLatestRecord = records.first;
                                  
                                  if (!context.mounted) return;
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => GrowthChartScreen(patient: freshLatestRecord),
                                    ),
                                  ).then((_) => setState(() {}));
                                },
                                icon: const Icon(Icons.timeline, size: 18),
                                label: const Text('Büyüme Grafiği'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade700,
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                              ),
                            ),

                            // Yeni Buton: Büyüme Değerlendirmesi
                            Tooltip(
                              message: 'Büyüme Gelişme Değerlendirmesi ve Persentil Analizi',
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  // Büyüme ve Gelişme Değerlendirmesi Ekranı aç
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => GrowthAssessmentScreen(initialRecord: latestRecord),
                                    ),
                                  ).then((_) => setState(() {}));
                                },
                                icon: const Icon(Icons.assessment, size: 18),
                                label: const Text('B/G Değerlendirmesi'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple.shade700,
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                              ),
                            ),

                            // Yeni Buton 3: Fenilalanin Grafiğini Aç
                            Tooltip(
                              message: 'Fenilalanin (FA) Grafiğini Aç',
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  // YENİ: FA Grafik ekranına yönlendir
                                  Navigator.of(context).push(
                                     MaterialPageRoute(
                                       builder: (context) => FaGraphScreen(patientRecord: latestRecord),
                                     ),
                                   ).then((_) => setState(() {}));
                                },
                                icon: const Icon(Icons.data_thresholding, size: 18),
                                label: const Text('FA Grafiği'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple.shade700,
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                              ),
                            ),

                            // Yeni Buton 4: Tirozin Grafiğini Aç
                            Tooltip(
                              message: 'Tirozin Grafiğini Aç',
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                     MaterialPageRoute(
                                       builder: (context) => TyrosineGraphScreen(patientRecord: latestRecord),
                                     ),
                                   ).then((_) => setState(() {}));
                                },
                                icon: const Icon(Icons.data_thresholding, size: 18),
                                label: const Text('Tyr Grafiği'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade700,
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('Yeni Kayıt'),
          onPressed: () => _navigateToMetabolizma(context), 
      ),
    );
  }
}