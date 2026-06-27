// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'report_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DailyReportAdapter extends TypeAdapter<DailyReport> {
  @override
  final int typeId = 0;

  @override
  DailyReport read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DailyReport(
      branch: fields[0] as String,
      date: fields[1] as DateTime,
      openingBalances: (fields[2] as Map?)?.cast<String, double>(),
      loanCounts: (fields[3] as Map?)?.cast<String, int>(),
      closingBalances: (fields[4] as Map?)?.cast<String, double>(),
      totalDisbursed: fields[5] as double?,
      totalCollected: fields[6] as double?,
      collectedForOtherBranches: fields[7] as double?,
      pettyCash: fields[8] as double?,
      expenses: fields[9] as double?,
      synced: fields[10] == null ? false : fields[10] as bool,
      updatedAt: fields[11] as DateTime?,
      zanacoApplied: (fields[12] as Map?)?.cast<String, bool>(), totalLoans: null,
    );
  }

  @override
  void write(BinaryWriter writer, DailyReport obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.branch)
      ..writeByte(1)
      ..write(obj.date)
      ..writeByte(2)
      ..write(obj.openingBalances)
      ..writeByte(3)
      ..write(obj.loanCounts)
      ..writeByte(4)
      ..write(obj.closingBalances)
      ..writeByte(5)
      ..write(obj.totalDisbursed)
      ..writeByte(6)
      ..write(obj.totalCollected)
      ..writeByte(7)
      ..write(obj.collectedForOtherBranches)
      ..writeByte(8)
      ..write(obj.pettyCash)
      ..writeByte(9)
      ..write(obj.expenses)
      ..writeByte(10)
      ..write(obj.synced)
      ..writeByte(11)
      ..write(obj.updatedAt)
      ..writeByte(12)
      ..write(obj.zanacoApplied);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyReportAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
