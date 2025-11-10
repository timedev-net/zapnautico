import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../user_profiles/providers.dart';
import '../data/admin_messaging_repository.dart';

class AdminPushNotificationPage extends ConsumerStatefulWidget {
  const AdminPushNotificationPage({super.key});

  @override
  ConsumerState<AdminPushNotificationPage> createState() =>
      _AdminPushNotificationPageState();
}

class _AdminPushNotificationPageState
    extends ConsumerState<AdminPushNotificationPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _linkController = TextEditingController();
  bool _isSending = false;
  AdminBroadcastResult? _lastResult;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notificações push')),
        body: const Center(
          child: Text('Apenas administradores podem acessar esta tela.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Enviar push geral')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildInfoCard(context),
              const SizedBox(height: 24),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Título',
                  hintText: 'Atualização importante',
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLength: 70,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe o título exibido na notificação.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bodyController,
                decoration: const InputDecoration(
                  labelText: 'Mensagem',
                  hintText: 'Compartilhe rapidamente o que aconteceu...',
                ),
                maxLines: 4,
                maxLength: 240,
                textCapitalization: TextCapitalization.sentences,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Descreva o conteúdo da mensagem.';
                  }
                  if (value.trim().length < 10) {
                    return 'Use pelo menos 10 caracteres.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _linkController,
                decoration: const InputDecoration(
                  labelText: 'Link opcional',
                  hintText: 'https://zapnautico.app/... ou rota interna',
                  helperText:
                      'Informe um link que será enviado no payload da notificação.',
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _isSending ? null : _submit,
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('Enviar para todos os usuários'),
              ),
              if (_lastResult != null) ...[
                const SizedBox(height: 32),
                _BroadcastResultSummary(result: _lastResult!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.campaign_outlined,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'A mensagem será enviada para todos os dispositivos que aceitaram '
                'receber notificações. Utilize este recurso apenas para comunicados '
                'importantes e evite spam.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    final link = _linkController.text.trim();
    final repository = ref.read(adminMessagingRepositoryProvider);

    setState(() {
      _isSending = true;
    });

    try {
      final payload = <String, String>{};
      if (link.isNotEmpty) {
        payload['deep_link'] = link;
      }

      final result = await repository.sendBroadcastNotification(
        title: title,
        body: body,
        data: payload.isEmpty ? null : payload,
      );

      if (!mounted) return;

      setState(() {
        _lastResult = result;
      });

      final message = result.hasMessage
          ? result.message!
          : 'Envio concluído para ${result.targetedDevices} dispositivos.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on AdminPushException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar notificação: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }
}

class _BroadcastResultSummary extends StatelessWidget {
  const _BroadcastResultSummary({required this.result});

  final AdminBroadcastResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Resumo do último envio',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatTile(
                  label: 'Dispositivos',
                  value: result.targetedDevices.toString(),
                ),
                const SizedBox(width: 12),
                _StatTile(
                  label: 'Entregues',
                  value: result.delivered.toString(),
                ),
                const SizedBox(width: 12),
                _StatTile(
                  label: 'Falhas',
                  value: result.failed.toString(),
                ),
              ],
            ),
            if (result.hasMessage) ...[
              const SizedBox(height: 12),
              Text(
                result.message!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
