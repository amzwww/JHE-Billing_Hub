import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/bills_service.dart';
import '../utils/communication_summary.dart';
import '../utils/thread_ficha_extractor.dart';

const billingRequestStatuses = <String, String>{
  'no_viable': 'No viable',
  'cancelada': 'Cancelada',
  'pendiente': 'Pendiente',
  'negociando': 'Negociando',
  'a_facturar': 'A facturar',
  'a_cobrar': 'A cobrar',
  'cobrada': 'Cobrada',
};

const billingPaymentForms = <String, String>{
  '100_before': '100% antes de la ponencia',
  '50_initial': '50% inicial',
  '50_remaining_expenses': '50% restante + gastos',
};

const billingRequestTypes = <String, String>{
  'ponencia': 'Ponencia',
  'gastos': 'Gastos',
  'formacion': 'Formación',
  'consultoria': 'Consultoría',
  'sponsor': 'Sponsor',
  'mixta': 'Mixta',
  'master': 'Máster',
  'coworking': 'Coworking',
  'complemento': 'Complemento',
};

class BillingRequestEditorPage extends StatefulWidget {
  const BillingRequestEditorPage({
    super.key,
    this.existing,
    this.isAdmin = false,
  });

  final Map<String, dynamic>? existing;
  final bool isAdmin;

  @override
  State<BillingRequestEditorPage> createState() =>
      _BillingRequestEditorPageState();
}

class _BillingRequestEditorPageState extends State<BillingRequestEditorPage> {
  final _service = BillsService();
  final _formKey = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _contact = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _date = TextEditingController();
  final _population = TextEditingController();
  final _amount = TextEditingController();
  final _expenses = TextEditingController();
  final _taxCompany = TextEditingController();
  final _taxId = TextEditingController();
  final _taxAddress = TextEditingController();
  final _taxPostal = TextEditingController();
  final _taxPopulation = TextEditingController();
  final _taxProvince = TextEditingController();
  final _thread = TextEditingController();
  final _summary = TextEditingController();
  late String _status;
  late String _requestType;
  String? _invoiceIssuer;
  String? _paymentForm;
  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final row = widget.existing;
    _status = _s(row?['status']).isEmpty ? 'pendiente' : _s(row?['status']);
    _requestType = billingRequestTypes.containsKey(_s(row?['request_type']))
        ? _s(row?['request_type'])
        : 'ponencia';
    _invoiceIssuer = _s(row?['invoice_issuer']).isEmpty
        ? null
        : _s(row?['invoice_issuer']);
    _paymentForm = _s(row?['payment_form']).isEmpty
        ? null
        : _s(row?['payment_form']);
    _company.text = _s(row?['company_name']);
    _contact.text = _s(row?['contact_name']);
    _email.text = _s(row?['contact_email']);
    _phone.text = _s(row?['contact_phone']);
    _date.text = _s(row?['presentation_date']);
    _population.text = _s(row?['presentation_population']);
    _amount.text = _number(row?['presentation_amount']);
    _expenses.text = _number(row?['logistics_expenses']);
    _taxCompany.text = _s(row?['tax_company_name']);
    _taxId.text = _s(row?['tax_id']);
    _taxAddress.text = _s(row?['tax_address']);
    _taxPostal.text = _s(row?['tax_postal_code']);
    _taxPopulation.text = _s(row?['tax_population']);
    _taxProvince.text = _s(row?['tax_province']);
    _thread.text = _s(row?['communication_thread']);
    _summary.text = _s(row?['communication_summary']);
  }

  @override
  void dispose() {
    for (final controller in [
      _company,
      _contact,
      _email,
      _phone,
      _date,
      _population,
      _amount,
      _expenses,
      _taxCompany,
      _taxId,
      _taxAddress,
      _taxPostal,
      _taxPopulation,
      _taxProvince,
      _thread,
      _summary,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final parsedDate = _date.text.trim().isEmpty
        ? null
        : DateTime.tryParse(_date.text.trim());
    if (_date.text.trim().isNotEmpty && parsedDate == null) {
      _message('La fecha de ponencia debe tener formato AAAA-MM-DD.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.saveBillingRequest(
        {
          'status': _status,
          'request_type': _requestType,
          'invoice_issuer': _invoiceIssuer,
          'company_name': _company.text.trim(),
          'contact_name': _nullIfEmpty(_contact.text),
          'contact_email': _nullIfEmpty(_email.text),
          'contact_phone': _nullIfEmpty(_phone.text),
          'presentation_date': parsedDate == null
              ? null
              : DateFormat('yyyy-MM-dd').format(parsedDate),
          'presentation_population': _nullIfEmpty(_population.text),
          'presentation_amount': _numberOrNull(_amount.text),
          'logistics_expenses': _numberOrNull(_expenses.text),
          'payment_form': _paymentForm,
          'tax_company_name': _nullIfEmpty(_taxCompany.text),
          'tax_id': _nullIfEmpty(_taxId.text),
          'tax_address': _nullIfEmpty(_taxAddress.text),
          'tax_postal_code': _nullIfEmpty(_taxPostal.text),
          'tax_population': _nullIfEmpty(_taxPopulation.text),
          'tax_province': _nullIfEmpty(_taxProvince.text),
          'communication_thread': _nullIfEmpty(_thread.text),
          'communication_summary': _nullIfEmpty(_summary.text),
        },
        id: _s(widget.existing?['id']).isEmpty
            ? null
            : _s(widget.existing?['id']),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _message('No se pudo guardar la solicitud: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _summarize() {
    final summary = summarizeCommunicationThread(_thread.text);
    setState(() => _summary.text = summary);
  }

  Future<void> _editSummary() async {
    final editor = TextEditingController(text: _summary.text);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar resumen'),
        content: SizedBox(
          width: 760,
          child: TextField(
            controller: editor,
            autofocus: true,
            minLines: 12,
            maxLines: 22,
            decoration: const InputDecoration(
              hintText: 'Edita aquí las conclusiones del hilo.',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, editor.text.trim()),
            icon: const Icon(Icons.check),
            label: const Text('Aplicar cambios'),
          ),
        ],
      ),
    );
    editor.dispose();
    if (result != null && mounted) {
      setState(() => _summary.text = result);
    }
  }

  Future<void> _completeFicha() async {
    final text = _thread.text.trim();
    if (text.isEmpty) {
      _message('Pega primero el hilo de comunicación.');
      return;
    }
    final values = extractCommunicationFicha(text);
    setState(() {
      _summary.text = summarizeCommunicationThread(text);
      _fillDetected(_company, values['company']);
      _fillDetected(_contact, values['contact']);
      _fillDetected(_email, values['email']);
      _fillDetected(_phone, values['phone']);
      _fillDetected(_date, values['date']);
      _fillDetected(_population, values['population']);
      _fillDetected(_amount, values['amount']);
      _fillDetected(_expenses, values['expenses']);
      _fillDetected(_taxCompany, values['tax_company']);
      _fillDetected(_taxId, values['tax_id']);
      _fillDetected(_taxAddress, values['tax_address']);
      _fillDetected(_taxPostal, values['tax_postal']);
      _fillDetected(_taxPopulation, values['tax_population']);
      _fillDetected(_taxProvince, values['tax_province']);
    });
    final filled = values.values
        .where((value) => value != null && value.toString().isNotEmpty)
        .length;
    _message(
      'Ficha completada: $filled datos detectados. Revísalos antes de guardar.',
    );
  }

  void _fillDetected(TextEditingController controller, String? value) {
    if (value != null && value.trim().isNotEmpty) {
      controller.text = value.trim();
    }
  }

  Future<void> _changeStatus(String value) async {
    final previous = _status;
    if (value == previous) return;
    if (value == 'a_facturar') {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirmar A facturar'),
          content: const Text(
            'Recuerda que esto envía un aviso a facturación. ¿Quieres continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      final issuer = await _askIssuer();
      if (!mounted || issuer == null) return;
      setState(() {
        _status = value;
        _invoiceIssuer = issuer;
      });
      return;
    }
    setState(() => _status = value);
  }

  Future<String?> _askIssuer() async {
    final issuers = await _service.issuers();
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Emisor de la factura'),
        content: const Text('¿Quién emitirá esta factura?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          for (final issuer in issuers)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, _s(issuer['id'])),
              child: Text(_issuerName(issuer)),
            ),
        ],
      ),
    );
  }

  String _issuerName(Map<String, dynamic> issuer) {
    final id = _s(issuer['id']);
    if (id == 'JHE') return 'Jon';
    if (id == 'BN') return 'Bright';
    if (id == 'SKY') return 'Skynet';
    final name = _s(issuer['name']);
    return name.isEmpty ? id : name;
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Editar solicitud' : 'Nueva solicitud'),
        actions: [
          if (compact)
            IconButton(
              onPressed: _saving ? null : _save,
              tooltip: _saving ? 'Guardando...' : 'Guardar',
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 24),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Guardando...' : 'Guardar'),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 28,
            18,
            compact ? 12 : 28,
            48,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1500),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_editing) ...[
                    _communicationSection(),
                    const SizedBox(height: 18),
                  ],
                  _section('Estado y ponencia', Icons.flag_outlined, [
                    _row([
                      _dropdown('Estado', _status, billingRequestStatuses, (
                        value,
                      ) {
                        if (value != null) _changeStatus(value);
                      }),
                      _dropdown(
                        'Tipo',
                        _requestType,
                        billingRequestTypes,
                        (value) =>
                            setState(() => _requestType = value ?? 'ponencia'),
                      ),
                      _field(_date, 'Fecha ponencia (AAAA-MM-DD)', width: 230),
                      _field(_population, 'Población de la ponencia'),
                      _field(_amount, 'Importe (€)', width: 180),
                      _field(_expenses, 'Gastos de logística (€)', width: 210),
                    ]),
                    const SizedBox(height: 16),
                    _dropdown(
                      'Forma de pago',
                      _paymentForm,
                      billingPaymentForms,
                      (value) => setState(() => _paymentForm = value),
                      allowEmpty: true,
                    ),
                    if (_invoiceIssuer != null) ...[
                      const SizedBox(height: 12),
                      Chip(
                        avatar: const Icon(
                          Icons.business_center_outlined,
                          size: 17,
                        ),
                        label: Text(
                          'Emisor: ${_invoiceIssuer == 'JHE'
                              ? 'Jon'
                              : _invoiceIssuer == 'BN'
                              ? 'Bright'
                              : _invoiceIssuer == 'SKY'
                              ? 'Skynet'
                              : _invoiceIssuer}',
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 18),
                  _section('Contacto', Icons.contact_page_outlined, [
                    _row([
                      _field(_company, 'Nombre empresa', required: true),
                      _field(_contact, 'Persona de contacto'),
                      _field(_email, 'Mail de contacto'),
                      _field(_phone, 'Teléfono de contacto'),
                    ]),
                  ]),
                  const SizedBox(height: 18),
                  _section('Datos fiscales', Icons.business_outlined, [
                    _row([
                      _field(_taxCompany, 'RAZÓN SOCIAL'),
                      _field(_taxId, 'CIF'),
                      _field(_taxAddress, 'DIRECCIÓN'),
                      _field(_taxPostal, 'CÓDIGO POSTAL', width: 180),
                    ]),
                    const SizedBox(height: 16),
                    _row([
                      _field(_taxPopulation, 'POBLACIÓN'),
                      _field(_taxProvince, 'PROVINCIA'),
                    ]),
                  ]),
                  if (_editing) ...[
                    const SizedBox(height: 18),
                    _communicationSection(),
                  ],
                  if (_editing) ...[const SizedBox(height: 18), _metadata()],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _communicationSection() => _section(
    'Hilo de comunicación',
    Icons.forum_outlined,
    [
      TextField(
        controller: _thread,
        minLines: 8,
        maxLines: 18,
        decoration: const InputDecoration(
          labelText: 'Pega aquí el hilo de Gmail',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: _completeFicha,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Completar ficha'),
          ),
          OutlinedButton.icon(
            onPressed: _summarize,
            icon: const Icon(Icons.subject_outlined),
            label: const Text('Generar resumen cronológico'),
          ),
          const Text(
            'La ficha se rellena con los datos detectados y siempre puedes revisarla.',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _summaryPreview(),
    ],
  );

  Widget _summaryPreview() {
    final summary = _summary.text.trim();
    if (summary.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: Border.all(color: const Color(0xFFD4DCE8)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Genera el resumen para ver aquí las conclusiones del correo.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFD4DCE8)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.summarize_outlined, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Resumen del hilo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: _editSummary,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar resumen'),
              ),
            ],
          ),
          const Divider(height: 24),
          SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in summary.split('\n')) _summaryLine(line),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(String source) {
    final line = source.trim();
    if (line.isEmpty) return const SizedBox(height: 10);
    if (line == 'CRONOLOGÍA RESUMIDA' || line == 'SITUACIÓN ACTUAL') {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 10),
        child: Text(
          line == 'CRONOLOGÍA RESUMIDA'
              ? 'Cronología resumida'
              : 'Situación actual',
          style: const TextStyle(
            color: Color(0xFF142A5C),
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    final separator = line.indexOf(' — ');
    if (line.startsWith('• ') && separator < 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 3),
        child: Text(
          line.substring(2),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      );
    }

    if (separator >= 0) {
      final label = line.substring(line.startsWith('• ') ? 2 : 0, separator);
      final detail = line.substring(separator + 3);
      return Padding(
        padding: EdgeInsets.only(
          left: line.startsWith('• ') ? 0 : 16,
          bottom: 5,
        ),
        child: Text.rich(
          TextSpan(
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 14,
              height: 1.45,
            ),
            children: [
              TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(text: detail),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        line,
        style: const TextStyle(
          color: Color(0xFF1E293B),
          fontSize: 14,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _metadata() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Wrap(
        spacing: 36,
        runSpacing: 10,
        children: [
          Text('Creado por: ${_s(widget.existing?['created_by'])}'),
          Text('Fecha creación: ${_s(widget.existing?['created_at'])}'),
          Text('Última modificación: ${_s(widget.existing?['updated_by'])}'),
          Text(
            'Fecha última modificación: ${_s(widget.existing?['updated_at'])}',
          ),
        ],
      ),
    ),
  );

  Widget _section(String title, IconData icon, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 21),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    ),
  );

  Widget _row(List<Widget> children) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 700) {
        return Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: children[i]),
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: children[i]),
          ],
        ],
      );
    },
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    double? width,
    bool required = false,
  }) => SizedBox(
    width: width,
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      validator: required
          ? (value) =>
                value == null || value.trim().isEmpty ? 'Obligatorio' : null
          : null,
    ),
  );

  Widget _dropdown(
    String label,
    String? value,
    Map<String, String> values,
    ValueChanged<String?>? changed, {
    bool allowEmpty = false,
  }) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      if (allowEmpty)
        const DropdownMenuItem(value: null, child: Text('Sin especificar')),
      for (final entry in values.entries)
        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
    ],
    onChanged: changed,
  );

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

String _s(dynamic value) => value?.toString() ?? '';
String _number(dynamic value) => value == null ? '' : value.toString();
double? _numberOrNull(String value) =>
    double.tryParse(value.trim().replaceAll(',', '.'));
String? _nullIfEmpty(String value) =>
    value.trim().isEmpty ? null : value.trim();
