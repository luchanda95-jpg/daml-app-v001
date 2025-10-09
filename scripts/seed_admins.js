// scripts/seed_admins.js
require('dotenv').config();
const mongoose = require('mongoose');
const User = require('../models/User');

const mongoUri = process.env.MONGO_URI || process.env.MONGODB_URI;
if (!mongoUri) {
  console.error('MONGO_URI not set');
  process.exit(1);
}

async function run() {
  await mongoose.connect(mongoUri);
  console.log('Connected to mongo');

  const overallEmail = (process.env.OVERALL_ADMIN_EMAIL || 'directaccessmoney@gmail.com').toLowerCase().trim();
  const branchEmails = [
    'monze@directaccess.com',
    'mazabuka@directaccess.com',
    'lusaka@directaccess.com',
    'solwezi@directaccess.com',
    'lumezi@directaccess.com',
    'nakonde@directaccess.com'
  ];

  // create overall admin
  let ov = await User.findOne({ email: overallEmail });
  if (!ov) {
    ov = new User({ email: overallEmail, name: 'Overall Admin', role: 'ovadmin' });
    await ov.setPassword('ovadmin');
    await ov.save();
    console.log(`Created overall admin ${overallEmail} / ovadmin`);
  } else {
    console.log(`Overall admin ${overallEmail} already exists`);
  }

  for (const e of branchEmails) {
    const normalized = e.toLowerCase().trim();
    let u = await User.findOne({ email: normalized });
    if (!u) {
      u = new User({ email: normalized, name: 'Branch Admin', role: 'branch_admin' });
      await u.setPassword('admin');
      await u.save();
      console.log(`Created branch admin ${normalized} / admin`);
    } else {
      console.log(`Branch admin ${normalized} already exists`);
    }
  }

  await mongoose.disconnect();
  console.log('Done, disconnected');
  process.exit(0);
}

run().catch(err => {
  console.error('Seed failed', err);
  process.exit(1);
});
