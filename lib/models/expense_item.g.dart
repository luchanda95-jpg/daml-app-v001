// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ExpenseItemAdapter extends TypeAdapter<ExpenseItem> {
  @override
  final int typeId = 10;

  @override
  ExpenseItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ExpenseItem(
      description: fields[0] as String,
      amount: fields[1] as double,
      date: fields[2] as DateTime,
      branch: fields[3] as String,
      account: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ExpenseItem obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.description)
      ..writeByte(1)
      ..write(obj.amount)
      ..writeByte(2)
      ..write(obj.date)
      ..writeByte(3)
      ..write(obj.branch)
      ..writeByte(4)
      ..write(obj.account);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpenseItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
