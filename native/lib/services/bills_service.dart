import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class BillsService {
  SupabaseClient get client => Supabase.instance.client;

  Future<String> currentRole() async {
    final user = client.auth.currentUser;
    if (user == null) return 'gestion';
    final rows = await client
        .from('user_roles')
        .select('role')
        .eq('user_id', user.id);
    final values = (rows as List).map((row) => row['role']?.toString());
    if (values.contains('admin')) return 'admin';
    return 'gestion';
  }

  Future<bool> isAdmin() async => (await currentRole()) == 'admin';

  Future<List<Map<String, dynamic>>> notifications() async {
    final rows = await client
        .from('notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<int> unreadNotificationsCount() async {
    final rows = await client
        .from('notifications')
        .select('id')
        .isFilter('read_at', null);
    return (rows as List).length;
  }

  Future<void> markNotificationRead(String id) async {
    final updated = await client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .select('id, read_at')
        .maybeSingle();
    if (updated == null || updated['read_at'] == null) {
      throw StateError('El aviso no se ha actualizado en la base de datos.');
    }
  }

  Future<void> markAllNotificationsRead() async {
    await client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .isFilter('read_at', null)
        .select('id');
  }

  Future<void> requestQuoteInvoice(String quoteId) async {
    await client.rpc('request_quote_invoice', params: {'_quote_id': quoteId});
  }

  Future<void> requestDocumentModification({
    required String documentType,
    required String documentId,
    required String documentNumber,
    required String requestText,
  }) async {
    await client.from('document_modification_requests').insert({
      'document_type': documentType,
      'document_id': documentId,
      'document_number': documentNumber,
      'request_text': requestText,
    });
  }

  Future<List<Map<String, dynamic>>> managedUsers() async {
    final result = await _manageUsers({'action': 'list'});
    return List<Map<String, dynamic>>.from(
      result['users'] as List? ?? const [],
    );
  }

  Future<void> createManagedUser({
    required String nickname,
    required String email,
    required String password,
    required String role,
  }) async {
    await _manageUsers({
      'action': 'create',
      'nickname': nickname,
      'email': email,
      'password': password,
      'role': role,
    });
  }

  Future<void> updateManagedUser({
    required String userId,
    required String nickname,
    required String email,
    String? password,
    required String role,
  }) async {
    await _manageUsers({
      'action': 'update',
      'user_id': userId,
      'nickname': nickname,
      'email': email,
      if (password != null && password.isNotEmpty) 'password': password,
      'role': role,
    });
  }

  Future<void> deleteManagedUser(String userId) async {
    await _manageUsers({'action': 'delete', 'user_id': userId});
  }

  Future<Map<String, dynamic>> _manageUsers(Map<String, dynamic> body) async {
    final result = await client.functions.invoke('manage-users', body: body);
    final data = result.data is Map
        ? Map<String, dynamic>.from(result.data as Map)
        : <String, dynamic>{};
    if (result.status < 200 || result.status >= 300 || data['error'] != null) {
      throw Exception(
        data['error']?.toString() ??
            'La gestión de usuarios respondió ${result.status}.',
      );
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> invoices() =>
      _list('invoices', 'invoice_date');
  Future<List<Map<String, dynamic>>> quotes() => _list('quotes', 'quote_date');
  Future<List<Map<String, dynamic>>> issuers() =>
      _list('issuers', 'id', ascending: true);
  Future<List<Map<String, dynamic>>> importLog() =>
      _list('invoice_import_log', 'imported_at');

  Future<List<Map<String, dynamic>>> notionPonencias() async {
    final response = await client.functions.invoke(
      'notion-ponencias',
      body: const {},
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error'] : null;
      throw Exception(
        message?.toString() ??
            'La conexión con Notion respondió ${response.status}.',
      );
    }
    final data = response.data;
    if (data is! Map || data['rows'] is! List) {
      throw Exception('Respuesta de Notion no válida.');
    }
    return (data['rows'] as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  /// Árbol local de ponencias importadas desde Notion.
  /// La app ya no necesita una sesión de navegador ni permisos en el espacio
  /// de trabajo original para consultar estos datos.
  Future<List<Map<String, dynamic>>> billingRequestPonencias() async {
    final rows = await client
        .from('billing_requests')
        .select()
        .order('presentation_date', ascending: true);
    return (rows as List).map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      final source = row['source_data'] is Map
          ? Map<String, dynamic>.from(row['source_data'] as Map)
          : const <String, dynamic>{};
      return <String, dynamic>{
        'id': row['id'],
        'company': row['company_name'],
        'contact': row['contact_name'],
        'status': _billingRequestStatusLabel(row['status']),
        'date': _displayDate(row['presentation_date']),
        'address': row['presentation_population'],
        'fee': _displayAmount(row['presentation_amount']),
        'expenses': _displayAmount(row['logistics_expenses']),
        'invoice': source['Factura'],
        'description': row['communication_summary'],
        'details': source['Detalles'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> billingRequests() async {
    final rows = await client
        .from('billing_requests')
        .select()
        .order('updated_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<int> billingRequestsToInvoiceCount() async {
    final rows = await client
        .from('billing_requests')
        .select('id')
        .eq('status', 'a_facturar');
    return (rows as List).length;
  }

  Future<void> saveBillingRequest(
    Map<String, dynamic> payload, {
    String? id,
  }) async {
    final userId = client.auth.currentUser?.id;
    final values = Map<String, dynamic>.from(payload)..['updated_by'] = userId;
    if (id == null) {
      values['created_by'] = userId;
      await client.from('billing_requests').insert(values);
    } else {
      await client.from('billing_requests').update(values).eq('id', id);
    }
  }

  Future<void> deleteBillingRequest(String id) async {
    await client.from('billing_requests').delete().eq('id', id);
  }

  /// Crea una nueva gestión reutilizando los datos de otra.
  /// El duplicado vuelve a estado Pendiente para que pueda darse de alta como
  /// segundo pago, gastos u otro concepto sin alterar el original.
  Future<void> duplicateBillingRequest(Map<String, dynamic> row) async {
    await saveBillingRequest({
      'status': 'pendiente',
      'request_type': row['request_type'] ?? 'ponencia',
      'invoice_issuer': null,
      'company_name': row['company_name'],
      'contact_name': row['contact_name'],
      'contact_email': row['contact_email'],
      'contact_phone': row['contact_phone'],
      'presentation_date': row['presentation_date'],
      'presentation_population': row['presentation_population'],
      'presentation_amount': row['presentation_amount'],
      'logistics_expenses': row['logistics_expenses'],
      'payment_form': row['payment_form'],
      'tax_company_name': row['tax_company_name'],
      'tax_id': row['tax_id'],
      'tax_address': row['tax_address'],
      'tax_postal_code': row['tax_postal_code'],
      'tax_population': row['tax_population'],
      'tax_province': row['tax_province'],
      'communication_thread': row['communication_thread'],
      'communication_summary': row['communication_summary'],
    });
  }

  Future<void> updateBillingRequestStatus(
    String id,
    String status, {
    String? issuer,
  }) async {
    await client
        .from('billing_requests')
        .update({
          'status': status,
          'invoice_issuer': issuer,
          'updated_by': client.auth.currentUser?.id,
        })
        .eq('id', id);
  }

  Future<List<Map<String, dynamic>>> _list(
    String table,
    String order, {
    bool ascending = false,
  }) async {
    final rows = await client
        .from(table)
        .select()
        .order(order, ascending: ascending);
    return List<Map<String, dynamic>>.from(rows);
  }

  String _billingRequestStatusLabel(dynamic value) =>
      switch (value?.toString()) {
        'no_viable' => 'No viable',
        'cancelada' => 'Cancelada',
        'pendiente' => 'Pendiente',
        'negociando' => 'Negociando',
        'a_facturar' => 'A facturar',
        'a_cobrar' => 'A cobrar',
        'cobrada' => 'Cobrada',
        _ => value?.toString() ?? '',
      };

  String _displayDate(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return value?.toString() ?? '';
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  String _displayAmount(dynamic value) {
    if (value == null) return '';
    final amount = value is num
        ? value.toDouble()
        : double.tryParse(value.toString());
    return amount == null ? value.toString() : '${amount.toStringAsFixed(2)} €';
  }

  Future<Map<String, dynamic>?> invoice(String id) async {
    return await client.from('invoices').select().eq('id', id).maybeSingle();
  }

  Future<Map<String, dynamic>?> documentById({
    required String documentType,
    required String id,
  }) async {
    final table = documentType == 'quote' ? 'quotes' : 'invoices';
    final row = await client.from(table).select().eq('id', id).maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>?> documentByNumber({
    required String documentType,
    required String documentNumber,
  }) async {
    final isQuote = documentType == 'quote';
    final row = await client
        .from(isQuote ? 'quotes' : 'invoices')
        .select()
        .eq(isQuote ? 'quote_number' : 'invoice_number', documentNumber)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>?> modificationRequest(String id) async {
    final row = await client
        .from('document_modification_requests')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> saveInvoice(
    Map<String, dynamic> payload, {
    String? id,
  }) async {
    final saved = id == null
        ? await client.from('invoices').insert(payload).select().single()
        : await client
              .from('invoices')
              .update(payload)
              .eq('id', id)
              .select()
              .single();
    final expectedNumber = payload['invoice_number']?.toString();
    if (expectedNumber != null &&
        saved['invoice_number']?.toString() != expectedNumber) {
      throw Exception('La factura no quedó confirmada en la base de datos.');
    }
    return Map<String, dynamic>.from(saved);
  }

  Future<void> saveQuote(Map<String, dynamic> payload, {String? id}) async {
    if (id == null) {
      await client.from('quotes').insert(payload);
    } else {
      await client.from('quotes').update(payload).eq('id', id);
    }
  }

  Future<void> updateIssuer(String id, Map<String, dynamic> payload) async {
    await client.from('issuers').update(payload).eq('id', id);
  }

  Future<void> createIssuer(String id, Map<String, dynamic> payload) async {
    await client.from('issuers').insert({'id': id, ...payload});
  }

  Future<void> deleteDocument(String table, String id) async {
    await client.from(table).delete().eq('id', id);
  }

  Future<int> nextInvoiceSequence(String issuerId, int year) async {
    final value = await client.rpc(
      'next_invoice_seq',
      params: {'_issuer_id': issuerId, '_year': year},
    );
    return (value as num).toInt();
  }

  Future<List<int>> invoiceGaps(String issuerId, int year) async {
    final value = await client.rpc(
      'find_invoice_gaps',
      params: {'_issuer_id': issuerId, '_year': year},
    );
    if (value is! List) return const [];
    return value
        .map((raw) {
          if (raw is num) return raw.toInt();
          if (raw is Map && raw['missing_seq'] is num)
            return (raw['missing_seq'] as num).toInt();
          return -1;
        })
        .where((value) => value > 0)
        .toList();
  }

  Future<bool> invoiceSequenceExists(String issuerId, int year, int seq) async {
    final row = await client
        .from('invoices')
        .select('id')
        .eq('issuer_id', issuerId)
        .eq('year', year)
        .eq('seq', seq)
        .maybeSingle();
    return row != null;
  }

  Future<int> nextQuoteSequence(String issuerId, int year) async {
    final value = await client.rpc(
      'next_quote_seq',
      params: {'_issuer_id': issuerId, '_year': year},
    );
    return (value as num).toInt();
  }

  Future<int> nextRectificativeSequence(String issuerId, int year) async {
    final gaps = await client.rpc(
      'find_rectificative_invoice_gaps',
      params: {'_issuer_id': issuerId, '_year': year},
    );
    if (gaps is List && gaps.isNotEmpty) {
      final first = Map<String, dynamic>.from(gaps.first as Map);
      return (first['missing_seq'] as num).toInt();
    }
    final value = await client.rpc(
      'next_rectificative_invoice_seq',
      params: {'_issuer_id': issuerId, '_year': year},
    );
    return (value as num).toInt();
  }

  Future<void> markPaid(
    Map<String, dynamic> invoice,
    String paidAt, {
    Uint8List? proof,
    String? proofName,
  }) async {
    String? proofPath = invoice['payment_proof_url'] as String?;
    if (proof != null && proofName != null) {
      final extension = proofName.contains('.')
          ? proofName.split('.').last
          : 'pdf';
      proofPath = '${invoice['id']}.$extension';
      await client.storage
          .from('payment-proofs')
          .uploadBinary(
            proofPath,
            proof,
            fileOptions: const FileOptions(upsert: true),
          );
    }
    await client
        .from('invoices')
        .update({
          'paid': true,
          'paid_at': paidAt,
          'payment_proof_url': proofPath,
        })
        .eq('id', invoice['id']);
  }

  Future<void> undoPaid(Map<String, dynamic> invoice) async {
    final proofPath = invoice['payment_proof_url'] as String?;
    if (proofPath != null && proofPath.isNotEmpty) {
      await client.storage.from('payment-proofs').remove([proofPath]);
    }
    await client
        .from('invoices')
        .update({'paid': false, 'paid_at': null, 'payment_proof_url': null})
        .eq('id', invoice['id']);
  }

  Future<Uint8List> downloadStorage(String bucket, String path) {
    return client.storage.from(bucket).download(path);
  }

  Future<Map<String, dynamic>> extractClient(
    Uint8List bytes,
    String mimeType,
  ) async {
    final response = await client.functions.invoke(
      'extract-client',
      body: {'imageBase64': base64Encode(bytes), 'mimeType': mimeType},
    );
    if (response.status < 200 || response.status >= 300) {
      throw Exception(
        'El servicio de extracción respondió ${response.status}.',
      );
    }
    final data = response.data;
    if (data is! Map) throw Exception('Respuesta de extracción no válida.');
    final result = Map<String, dynamic>.from(data);
    if (result['error'] != null) throw Exception(result['error']);
    return result;
  }

  Future<void> updateClient(
    List<String> invoiceIds,
    Map<String, dynamic> values,
  ) async {
    await client.from('invoices').update(values).inFilter('id', invoiceIds);
  }

  Future<void> convertQuote(String quoteId, String invoiceNumber) async {
    await client
        .from('quotes')
        .update({
          'status': 'converted',
          'converted_invoice_number': invoiceNumber,
        })
        .eq('id', quoteId);
  }
}
