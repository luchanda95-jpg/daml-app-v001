// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'monthly_report_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MonthlyReportAdapter extends TypeAdapter<MonthlyReport> {
  @override
  final int typeId = 1;

  @override
  MonthlyReport read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MonthlyReport(
      branch: fields[0] as String,
      date: fields[1] as DateTime,
      expected: fields[2] as double?,
      inputs: fields[3] as int?,
      collected: fields[4] as double?,
      collectedInput: fields[5] as int?,
      totalUncollected: fields[6] as double?,
      uncollectedInput: fields[7] as int?,
      insufficient: fields[8] as double?,
      insufficientInput: fields[9] as int?,
      unreported: fields[10] as double?,
      unreportedInput: fields[11] as int?,
      lateCollection: fields[12] as double?,
      uncollected: fields[13] as double?,
      permicExpectedNextMonth: fields[14] as double?,
      totalInputs: fields[15] as int?,
      oldInputsAmount: fields[16] as double?,
      oldInputsCount: fields[17] as int?,
      newInputsAmount: fields[18] as double?,
      newInputsCount: fields[19] as int?,
      cashAdvance: fields[20] as double?,
      overallExpected: fields[21] as double?,
      actualExpected: fields[22] as double?,
      collected2: fields[23] as double?,
      principalReloaned: fields[24] as double?,
      defaultAmount: fields[25] as double?,
      clearance: fields[26] as double?,
      totalCollections: fields[27] as double?,
      permicCashAdvance: fields[28] as double?,
      synced: fields[29] == null ? false : fields[29] as bool,
      updatedAt: fields[30] as DateTime?,
      createdAt: fields[31] as DateTime?,
      year: fields[32] as int?,
      month: fields[33] as int?,
      totalCollected: fields[34] as double?,
      totalDisbursed: fields[35] as double?,
      totalExpenses: fields[36] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, MonthlyReport obj) {
    writer
      ..writeByte(37)
      ..writeByte(0)
      ..write(obj.branch)
      ..writeByte(1)
      ..write(obj.date)
      ..writeByte(2)
      ..write(obj.expected)
      ..writeByte(3)
      ..write(obj.inputs)
      ..writeByte(4)
      ..write(obj.collected)
      ..writeByte(5)
      ..write(obj.collectedInput)
      ..writeByte(6)
      ..write(obj.totalUncollected)
      ..writeByte(7)
      ..write(obj.uncollectedInput)
      ..writeByte(8)
      ..write(obj.insufficient)
      ..writeByte(9)
      ..write(obj.insufficientInput)
      ..writeByte(10)
      ..write(obj.unreported)
      ..writeByte(11)
      ..write(obj.unreportedInput)
      ..writeByte(12)
      ..write(obj.lateCollection)
      ..writeByte(13)
      ..write(obj.uncollected)
      ..writeByte(14)
      ..write(obj.permicExpectedNextMonth)
      ..writeByte(15)
      ..write(obj.totalInputs)
      ..writeByte(16)
      ..write(obj.oldInputsAmount)
      ..writeByte(17)
      ..write(obj.oldInputsCount)
      ..writeByte(18)
      ..write(obj.newInputsAmount)
      ..writeByte(19)
      ..write(obj.newInputsCount)
      ..writeByte(20)
      ..write(obj.cashAdvance)
      ..writeByte(21)
      ..write(obj.overallExpected)
      ..writeByte(22)
      ..write(obj.actualExpected)
      ..writeByte(23)
      ..write(obj.collected2)
      ..writeByte(24)
      ..write(obj.principalReloaned)
      ..writeByte(25)
      ..write(obj.defaultAmount)
      ..writeByte(26)
      ..write(obj.clearance)
      ..writeByte(27)
      ..write(obj.totalCollections)
      ..writeByte(28)
      ..write(obj.permicCashAdvance)
      ..writeByte(29)
      ..write(obj.synced)
      ..writeByte(30)
      ..write(obj.updatedAt)
      ..writeByte(31)
      ..write(obj.createdAt)
      ..writeByte(32)
      ..write(obj.year)
      ..writeByte(33)
      ..write(obj.month)
      ..writeByte(34)
      ..write(obj.totalCollected)
      ..writeByte(35)
      ..write(obj.totalDisbursed)
      ..writeByte(36)
      ..write(obj.totalExpenses);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MonthlyReportAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
