// Google Apps Script Web App that receives event registrations from
// register.html and writes them into "Fantasy Alive — Registrations".
//
// This file is not deployed by git/Vercel — it only runs inside Google's
// Apps Script editor. It's kept here so the logic is version-controlled
// and easy to find. See the setup steps given alongside this file for how
// to paste it in and deploy it.
//
// For each event date, this creates (on first use) a "<date> - Roster"
// tab listing everyone registered, and a "<date> - Kitchen" tab listing
// only people who selected a meal, with blank checkbox cells for the
// meals they're actually getting, meant to be printed and marked off.

var SHEET_ID = '1QJQj1j4bTUrvIdQZvdTPhFN_ncGcXKvOmSPUvoULLk4';
var MEAL_SLOT_COLUMNS = ['Saturday Breakfast', 'Saturday Lunch', 'Saturday Dinner', 'Sunday Breakfast'];

function doPost(e) {
  var body = JSON.parse(e.postData.contents);
  var ss = SpreadsheetApp.openById(SHEET_ID);

  appendToRoster(ss, body);
  appendToKitchen(ss, body);

  return ContentService
    .createTextOutput(JSON.stringify({ ok: true }))
    .setMimeType(ContentService.MimeType.JSON);
}

function appendToRoster(ss, body) {
  var sheetName = body.eventLabel + ' - Roster';
  var sheet = ss.getSheetByName(sheetName);
  if (!sheet) {
    sheet = ss.insertSheet(sheetName);
    sheet.appendRow([
      'Timestamp', 'Player Email', 'Player Name', 'Character / Cast',
      'Pass', 'Price', 'Combat Status', 'Days Attending',
      'Meal Plan', 'Meal Price', 'Single Meal Choice', 'Total'
    ]);
    sheet.setFrozenRows(1);
  }
  sheet.appendRow([
    new Date(),
    body.playerEmail || '',
    body.playerName || '',
    body.characterName || '',
    body.passName || '',
    body.passPrice || 0,
    body.combatStatus || '',
    (body.daysAttending || []).join(', '),
    body.mealName || 'None',
    body.mealPrice || 0,
    body.singleMealChoice || '',
    body.total || 0
  ]);
}

function appendToKitchen(ss, body) {
  var mealSlots = body.mealSlots || {};
  var hasMeal = MEAL_SLOT_COLUMNS.some(function (slot) { return !!mealSlots[slot]; });
  if (!hasMeal) return; // nobody eating, don't clutter the kitchen sheet

  var sheetName = body.eventLabel + ' - Kitchen';
  var sheet = ss.getSheetByName(sheetName);
  if (!sheet) {
    sheet = ss.insertSheet(sheetName);
    sheet.appendRow(['Name'].concat(MEAL_SLOT_COLUMNS));
    sheet.setFrozenRows(1);
  }
  var row = [body.characterName || body.playerName || ''];
  MEAL_SLOT_COLUMNS.forEach(function (slot) {
    row.push(mealSlots[slot] ? '☐' : ''); // ☐, ticked off by hand at the event
  });
  sheet.appendRow(row);
}
