import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/di/injection.dart';
import 'customer_form_cubit.dart';
import 'customer_form_state.dart';

class CustomerEditScreen extends StatelessWidget {
  final String? customerId;

  const CustomerEditScreen({
    super.key,
    this.customerId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => sl<CustomerFormCubit>(param1: customerId),
      child: Scaffold(
        appBar: AppBar(
          title: Text(customerId == null ? 'New Customer' : 'Edit Customer'),
          actions: [
            if (customerId != null)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => context.read<CustomerFormCubit>().reset(),
                tooltip: 'Reset',
              ),
          ],
        ),
        body: const _CustomerFormBody(),
      ),
    );
  }
}

class _CustomerFormBody extends StatelessWidget {
  const _CustomerFormBody();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CustomerFormCubit, CustomerFormState>(
      listener: (context, state) {
        if (state is CustomerFormStateSaved) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Customer saved successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, state.customer);
        }
      },
      builder: (context, state) {
        return switch (state) {
          CustomerFormStateInitial() => const Center(
              child: CircularProgressIndicator(),
            ),
          CustomerFormStateLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
          CustomerFormStateSaving() => const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Saving customer...'),
                ],
              ),
            ),
          CustomerFormStateError(message: final message) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: $message', style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.read<CustomerFormCubit>().reset(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          CustomerFormStateValidationError(message: final message) => _buildFormWithError(context, state, message),
          CustomerFormStateDuplicatePhoneError() => _buildFormWithError(
              context,
              state,
              'A customer with this phone number already exists',
            ),
          CustomerFormStateCreating() => _buildForm(context, state),
          CustomerFormStateEditing() => _buildForm(context, state),
          CustomerFormStateSaved() => const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 64),
                  SizedBox(height: 16),
                  Text('Customer saved successfully!'),
                ],
              ),
            ),
        };
      },
    );
  }

  Widget _buildFormWithError(BuildContext context, CustomerFormState state, String errorMessage) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.red[50],
          child: Row(
            children: [
              const Icon(Icons.error, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildForm(context, state)),
      ],
    );
  }

  Widget _buildForm(BuildContext context, CustomerFormState state) {
    final fullName = state is CustomerFormStateCreating ? state.fullName : 
                     state is CustomerFormStateEditing ? state.fullName : '';
    final phoneNumber = state is CustomerFormStateCreating ? state.phoneNumber : 
                        state is CustomerFormStateEditing ? state.phoneNumber : '';
    final notes = state is CustomerFormStateCreating ? state.notes : 
                  state is CustomerFormStateEditing ? state.notes : '';
    final photoPath = state is CustomerFormStateCreating ? state.photoPath : 
                      state is CustomerFormStateEditing ? state.photoPath : '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPhotoSection(context, photoPath),
          const SizedBox(height: 24),
          _buildFullNameField(context, fullName),
          const SizedBox(height: 16),
          _buildPhoneNumberField(context, phoneNumber),
          const SizedBox(height: 16),
          _buildNotesField(context, notes),
          const SizedBox(height: 32),
          _buildSaveButton(context),
        ],
      ),
    );
  }

  Widget _buildPhotoSection(BuildContext context, String photoPath) {
    return Column(
      children: [
        CircleAvatar(
          radius: 60,
          backgroundImage: photoPath.isNotEmpty
              ? NetworkImage(photoPath)
              : null,
          backgroundColor: photoPath.isEmpty ? Colors.blue[100] : null,
          child: photoPath.isEmpty
              ? const Icon(Icons.person, size: 60, color: Colors.blue)
              : null,
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => _pickImage(context),
          icon: const Icon(Icons.camera_alt),
          label: const Text('Add Photo'),
        ),
      ],
    );
  }

  Widget _buildFullNameField(BuildContext context, String fullName) {
    return TextFormField(
      decoration: const InputDecoration(
        labelText: 'Full Name *',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.person),
      ),
      initialValue: fullName,
      onChanged: (value) => context.read<CustomerFormCubit>().updateFullName(value),
      textInputAction: TextInputAction.next,
    );
  }

  Widget _buildPhoneNumberField(BuildContext context, String phoneNumber) {
    return TextFormField(
      decoration: const InputDecoration(
        labelText: 'Phone Number *',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.phone),
      ),
      initialValue: phoneNumber,
      onChanged: (value) => context.read<CustomerFormCubit>().updatePhoneNumber(value),
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
    );
  }

  Widget _buildNotesField(BuildContext context, String notes) {
    return TextFormField(
      decoration: const InputDecoration(
        labelText: 'Notes (Optional)',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.note),
        alignLabelWithHint: true,
      ),
      initialValue: notes,
      onChanged: (value) => context.read<CustomerFormCubit>().updateNotes(value),
      maxLines: 3,
      textInputAction: TextInputAction.done,
    );
  }

  Widget _buildSaveButton(BuildContext context) {
    return ElevatedButton(
      onPressed: () => context.read<CustomerFormCubit>().saveCustomer(),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: const Text(
        'Save Customer',
        style: TextStyle(fontSize: 16),
      ),
    );
  }

  Future<void> _pickImage(BuildContext context) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      // In a real app, you would upload this to a server
      // For now, we'll just use the local path
      context.read<CustomerFormCubit>().updatePhotoPath(pickedFile.path);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo selected (would be uploaded in real app)'),
        ),
      );
    }
  }
}