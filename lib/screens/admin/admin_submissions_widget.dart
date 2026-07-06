// lib/screens/admin/admin_submissions_widget.dart
// Supabase-backed admin UI to view client application submissions and PDF links.
// Updated: displays submissions as a clean paper-style application instead of raw JSON.

// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:daml/widgets/app_skeleton.dart';
import 'package:flutter/services.dart';

import 'package:daml/services/supabase_daml_service.dart';
import 'admin_loan_accounts_widget.dart';

class AdminSubmissionsWidget extends StatefulWidget {
  final List<Map<String, dynamic>> submissions;
  final Future<void> Function(String id, Map<String, dynamic> item)? onMarkHandled;

  const AdminSubmissionsWidget({
    super.key,
    this.submissions = const [],
    this.onMarkHandled,
  });

  @override
  State<AdminSubmissionsWidget> createState() => _AdminSubmissionsWidgetState();
}

class _AdminSubmissionsWidgetState extends State<AdminSubmissionsWidget> {
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      if (SupabaseDamlService.isConfigured) {
        _items = await SupabaseDamlService.fetchApplicationSubmissions();
      } else {
        _items = List<Map<String, dynamic>>.from(widget.submissions);
      }
    } catch (e) {
      _items = List<Map<String, dynamic>>.from(widget.submissions);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load submissions: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markHandled(String id, Map<String, dynamic> item, {String status = 'handled'}) async {
    if (id.isEmpty) return;

    if (widget.onMarkHandled != null) {
      await widget.onMarkHandled!(id, item);
    } else if (SupabaseDamlService.isConfigured) {
      await SupabaseDamlService.markApplicationHandled(id, status: status);
    }

    final index = _items.indexWhere((e) => e['id']?.toString() == id);
    if (index >= 0) {
      _items[index] = {..._items[index], 'status': status};
    }
    if (mounted) setState(() {});
  }

  dynamic _rawField(Map<String, dynamic> item, String key) {
    final raw = item['raw'];
    if (raw is Map && raw[key] != null) return raw[key];
    return null;
  }

  Map<String, dynamic> _formData(Map<String, dynamic> item) {
    final data = item['data'];
    if (data is Map) return Map<String, dynamic>.from(data);

    final raw = item['raw'];
    if (raw is Map) {
      final formData = raw['form_data'];
      if (formData is Map) return Map<String, dynamic>.from(formData);
      return Map<String, dynamic>.from(raw);
    }

    return item;
  }

  String _value(Map<String, dynamic> data, String key, {String fallback = '—'}) {
    final value = data[key];
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
  }

  String _displayDate(dynamic raw) {
    if (raw == null) return '—';
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return raw.toString();
    final local = parsed.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Future<void> _copyPdfLink(Map<String, dynamic> item) async {
    final path = (item['pdf_path'] ?? _rawField(item, 'pdf_path') ?? '').toString();
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No PDF path found for this submission')));
      return;
    }

    try {
      final signedUrl = await SupabaseDamlService.createPdfSignedUrl(path, expiresInSeconds: 3600);
      await Clipboard.setData(ClipboardData(text: signedUrl));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Formal PDF download link copied. It expires in 1 hour.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to create PDF link: $e')));
      }
    }
  }


  Future<void> _downloadPdf(Map<String, dynamic> item) async {
    final path = (item['pdf_path'] ?? _rawField(item, 'pdf_path') ?? '').toString();
    final filename = (item['pdf_filename'] ?? _rawField(item, 'pdf_filename') ?? '').toString();
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No PDF path found for this submission')));
      return;
    }

    try {
      final file = await SupabaseDamlService.downloadPdfToDevice(path, filename: filename);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF downloaded to device: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to download PDF: $e')));
      }
    }
  }

  Widget _statusChip(String status) {
    final normalized = status.trim().isEmpty ? 'pending' : status.trim().toLowerCase();
    final handled = normalized == 'handled' || normalized == 'confirmed' || normalized == 'approved' || normalized == 'done';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: handled ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: handled ? const Color(0xFF81C784) : const Color(0xFFFFCA28)),
      ),
      child: Text(
        normalized.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: handled ? const Color(0xFF2E7D32) : const Color(0xFF8D6E00),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(
        children: [
          Container(width: 5, height: 18, color: const Color(0xFF1D4E89)),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
        ],
      ),
    );
  }

  Widget _field(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
        color: Colors.white,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF424242))),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 12.5, color: Color(0xFF111111))),
          ),
        ],
      ),
    );
  }

  Widget _twoColumnFields(List<Widget> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(children: fields.map((w) => Padding(padding: const EdgeInsets.only(bottom: 6), child: w)).toList());
        }

        final rows = <Widget>[];
        for (var i = 0; i < fields.length; i += 2) {
          rows.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: fields[i]),
              const SizedBox(width: 8),
              Expanded(child: i + 1 < fields.length ? fields[i + 1] : const SizedBox.shrink()),
            ],
          ));
          rows.add(const SizedBox(height: 8));
        }
        return Column(children: rows);
      },
    );
  }

  Widget _paperPreview(Map<String, dynamic> item) {
    final data = _formData(item);
    final raw = item['raw'] is Map ? Map<String, dynamic>.from(item['raw'] as Map) : <String, dynamic>{};
    final pdfName = (item['pdf_filename'] ?? raw['pdf_filename'] ?? '').toString();
    final pdfPath = (item['pdf_path'] ?? raw['pdf_path'] ?? '').toString();
    final submittedAt = item['ts'] ?? raw['created_at'];
    final appId = (item['id'] ?? raw['id'] ?? '').toString();

    return Container(
      color: const Color(0xFFF5F5F5),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 820),
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFE0E0E0)),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1D4E89)),
                    alignment: Alignment.center,
                    child: const Text('DA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('DIRECT ACCESS MONEY LENDING', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
                        SizedBox(height: 3),
                        Text('CLIENT LOAN APPLICATION FORM', style: TextStyle(fontSize: 12.5, color: Color(0xFF616161), fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  _statusChip((item['status'] ?? raw['status'] ?? 'pending').toString()),
                ],
              ),
              const SizedBox(height: 14),
              Container(height: 2, color: const Color(0xFF1D4E89)),
              const SizedBox(height: 12),
              _twoColumnFields([
                _field('Application Ref', appId.isEmpty ? '—' : appId),
                _field('Submitted Date', _displayDate(submittedAt)),
                _field('Submitted Email', (raw['submitted_by_email'] ?? item['submitted_by_email'] ?? _value(data, 'email')).toString()),
                _field('PDF Document', pdfName.isEmpty ? (pdfPath.isEmpty ? 'No PDF attached' : pdfPath.split('/').last) : pdfName),
              ]),
              _sectionTitle('CLIENT DETAILS'),
              _twoColumnFields([
                _field('Full Name', _value(data, 'name')),
                _field('Gender', _value(data, 'gender')),
                _field('NRC Number', _value(data, 'nrc')),
                _field('Mobile Number', _value(data, 'mobile')),
                _field('Email Address', _value(data, 'email')),
                _field('Marital Status', _value(data, 'maritalStatus')),
                _field('Residence Type', _value(data, 'residenceType')),
                _field('Residential Address', _value(data, 'address')),
              ]),
              _sectionTitle('NEXT OF KIN DETAILS'),
              _twoColumnFields([
                _field('Primary NOK', _value(data, 'nok1Name')),
                _field('Primary NOK Mobile', _value(data, 'nok1Mobile')),
                _field('Primary NOK Address', _value(data, 'nok1Address')),
                _field('Secondary NOK', _value(data, 'nok2Name')),
                _field('Secondary NOK Mobile', _value(data, 'nok2Mobile')),
                _field('Secondary NOK Address', _value(data, 'nok2Address')),
              ]),
              _sectionTitle('EMPLOYMENT DETAILS'),
              _twoColumnFields([
                _field('Employer Name', _value(data, 'employerName')),
                _field('Employer Address', _value(data, 'employerAddress')),
                _field('Employee Number', _value(data, 'employeeNumber')),
                _field('Department', _value(data, 'department')),
                _field('Supervisor Name', _value(data, 'supervisorName')),
                _field('Supervisor Mobile', _value(data, 'supervisorMobile')),
              ]),
              _sectionTitle('BANKING DETAILS'),
              _twoColumnFields([
                _field('Bank Name', _value(data, 'bankName')),
                _field('Branch', _value(data, 'branchName')),
                _field('Account Number', _value(data, 'accountNumber')),
                _field('Sort Code', _value(data, 'sortCode')),
                _field('Bank NRC', _value(data, 'bankNrc')),
              ]),
              _sectionTitle('LOAN DETAILS'),
              _twoColumnFields([
                _field('Loan Amount', _value(data, 'loanAmount')),
                _field('Monthly Installment', _value(data, 'monthlyInstallment')),
                _field('Loan Start Date', _value(data, 'loanStart')),
                _field('Loan End Date', _value(data, 'loanEnd')),
                _field('Mode of Payment', _value(data, 'modeOfPayment')),
                _field('CRB Consent', _value(data, 'crbConsent')),
              ]),
              _sectionTitle('DECLARATION AND SIGNATURES'),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F9FC),
                  border: Border.all(color: const Color(0xFFD8E2F0)),
                ),
                child: const Text(
                  'Declaration: The applicant confirms that the information supplied in this application is true and complete. The uploaded PDF is the formal application document for review and processing by Direct Access Money Lending.',
                  style: TextStyle(fontSize: 12, height: 1.45),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(child: _signatureLine('Applicant Signature')),
                  const SizedBox(width: 24),
                  Expanded(child: _signatureLine('Authorised Officer')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _signatureLine(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: Colors.black87),
        const SizedBox(height: 6),
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('Date: __________________', style: TextStyle(fontSize: 11)),
      ],
    );
  }

  void _showDetails(Map<String, dynamic> item) {
    final client = (item['from'] ?? _formData(item)['name'] ?? 'Application').toString();
    final id = item['id']?.toString() ?? '';
    final hasPdf = (item['pdf_path'] ?? _rawField(item, 'pdf_path') ?? '').toString().isNotEmpty;

    showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 900,
          height: MediaQuery.of(context).size.height * 0.9,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF1D4E89),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Application Preview — $client',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(c).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(child: _paperPreview(item)),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE0E0E0)))),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: hasPdf ? () => _downloadPdf(item) : null,
                        icon: const Icon(Icons.download),
                        label: const Text('Download PDF'),
                      ),
                      TextButton.icon(
                        onPressed: hasPdf ? () => _copyPdfLink(item) : null,
                        icon: const Icon(Icons.link),
                        label: const Text('Copy PDF link'),
                      ),
                      TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Close')),
                      OutlinedButton.icon(
                        onPressed: id.isEmpty
                            ? null
                            : () async {
                                Navigator.of(c).pop();
                                try {
                                  await _markHandled(id, item, status: 'handled');
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as handled. Client has been notified.')));
                                  }
                                } catch (e) {
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Handler failed: $e')));
                                }
                              },
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Mark handled'),
                      ),
                      FilledButton.icon(
                        onPressed: id.isEmpty
                            ? null
                            : () async {
                                Navigator.of(c).pop();
                                try {
                                  await _markHandled(id, item, status: 'confirmed');
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Application confirmed. Client has been notified.')));
                                  }
                                } catch (e) {
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Confirmation failed: $e')));
                                }
                              },
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Confirm'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApplicationsBody() {
    return _loading
        ? const AppPageSkeleton()
        : _items.isEmpty
            ? const Center(child: Text('No applications submitted yet'))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final it = _items[i];
                  final data = _formData(it);
                  final from = (it['from'] ?? data['name'] ?? 'unknown').toString();
                  final ts = it['ts'] ?? _rawField(it, 'created_at');
                  final status = (it['status'] ?? _rawField(it, 'status') ?? 'pending').toString();
                  final amount = _value(data, 'loanAmount');
                  final phone = _value(data, 'mobile');
                  final hasPdf = (it['pdf_path'] ?? _rawField(it, 'pdf_path') ?? '').toString().isNotEmpty;

                  return Card(
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: hasPdf ? const Color(0xFFE8F0FE) : const Color(0xFFFFF3E0),
                        child: Icon(
                          hasPdf ? Icons.picture_as_pdf : Icons.description,
                          color: hasPdf ? const Color(0xFF1D4E89) : const Color(0xFFEF6C00),
                        ),
                      ),
                      title: Text(from, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Loan: $amount • Phone: $phone • ${_displayDate(ts)}'),
                      ),
                      trailing: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _statusChip(status),
                          const SizedBox(height: 6),
                          Text(hasPdf ? 'PDF ready' : 'No PDF', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                        ],
                      ),
                      onTap: () => _showDetails(it),
                    ),
                  );
                },
              );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Applications & Loans'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refresh,
              tooltip: 'Refresh applications',
            )
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.assignment_outlined), text: 'Applications'),
              Tab(icon: Icon(Icons.account_balance_wallet_outlined), text: 'Loan Accounts'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildApplicationsBody(),
            const AdminLoanAccountsWidget(),
          ],
        ),
      ),
    );
  }
}
