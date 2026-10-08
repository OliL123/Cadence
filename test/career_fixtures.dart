// Made-up career data for tests: the same shape as a real starting list (one
// application already sent, a no-sponsorship posting, a career fair whose
// sign-up window opens and closes within two days, a TBD coaching session, a
// handled deadline) — but fictional, since this repo is public and real
// starting lists are imported from private CSVs.
import 'package:cadence/store.dart';
import 'package:cadence/tracker/tracker_models.dart';

List<Application> sampleApplications(int Function() newId) => [
      Application(
          id: newId(), company: 'Lantern Games', role: 'Software Engineering Intern',
          track: 'game', term: 'Summer 2027', location: 'Remote',
          sponsorship: 'no-sponsorship', gradReq: '2028 grads', cvVersion: 'gaming',
          status: 'applied', dateApplied: '2026-10-06', deadline: '2026-11-06'),
      Application(
          id: newId(), company: 'Northwind', role: 'Explore / SWE Intern',
          track: 'early-program', term: 'Summer 2027'),
      Application(
          id: newId(), company: 'Contoso', role: 'SWE Intern',
          track: 'early-program', term: 'Summer 2027'),
      Application(
          id: newId(), company: 'Fabrikam', role: 'SWE Intern',
          track: 'early-program', term: 'Summer 2027'),
      Application(
          id: newId(), company: 'Tailspin Games', role: 'Intern (TBD)',
          track: 'game', term: 'Summer 2027', cvVersion: 'gaming'),
    ];

List<TrackEvent> sampleEvents(int Function() newId) => [
      TrackEvent(
          id: newId(), name: 'Virtual Engineering Career Fair', type: 'career-fair',
          start: '2026-10-09 12:00', end: '2026-10-09 17:00', location: 'Online',
          signupOpens: '2026-10-08 12:00', signupCloses: '2026-10-09 12:00'),
      TrackEvent(
          id: newId(), name: 'Online Hack Week', type: 'hackathon',
          start: '2026-10-09', end: '2026-10-15', location: 'Online'),
      TrackEvent(
          id: newId(), name: 'Autumn Game Jam', type: 'game-jam',
          start: '2026-11-01', end: '2026-11-30', location: 'Online'),
      TrackEvent(
          id: newId(), name: 'City Hackathon', type: 'hackathon',
          start: '2026-11-07', end: '2026-11-08', location: 'In person'),
      TrackEvent(
          id: newId(), name: 'Recruiter coaching session', type: 'coaching',
          relatedCompany: 'Tailspin Games'),
      TrackEvent(
          id: newId(), name: 'Winter Hackathon', type: 'hackathon',
          start: '2027-02-06', end: '2027-02-07', location: 'In person'),
      TrackEvent(
          id: newId(), name: 'Lantern application closes', type: 'deadline',
          start: '2026-11-06', status: 'signed-up', relatedCompany: 'Lantern Games'),
    ];

/// Load the sample list into [s] the way a user would: by importing it.
void loadSample(CadenceStore s) {
  s.importApplications(sampleApplications(() => 0));
  s.importEvents(sampleEvents(() => 0));
}
