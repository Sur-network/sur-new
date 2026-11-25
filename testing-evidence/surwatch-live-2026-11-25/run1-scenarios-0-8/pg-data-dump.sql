--
-- PostgreSQL database dump
--

\restrict FxXgwbtjXQefgGLt6MCc2VssPuOUD7hciNU1IIaXXZMUu2gUfOTYxwOWZ7vWbJT

-- Dumped from database version 15.18 (Debian 15.18-1.pgdg13+1)
-- Dumped by pg_dump version 15.18 (Debian 15.18-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: agent_keys; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.agent_keys (owner, operator, node_id, agent_address, registered_at, revoked_at, last_seq) FROM stdin;
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	0xf7ab920c3c19d225a9f6c2ee05599150f4d128f6	6a63fd39eae71f791ca03ddf0ff7c7f675177b28cc80f0fd0ba8ec30a122bfc070f161fb297305f4ae9685d47fec8133e49af6747866651a26d4977a6c8fd29d	0x7bbdb530c6d51c9891db1219f430c256f4e36104	2026-11-25 15:30:04.786584+00	\N	32
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	0x5bacebcfdad4d946b184276309a0b8b0a28ab608	2ee39b7b2596c0c76fb2ea87086e4c58a289cfd0289c916db47eaec04e1f4c8db14f441259e9be70e44b0ce2e24ba2f808884be2b0d700384f655b5460062614	0xa8ff9c78796e5aa423661b1a4df58b4b49fccc36	2026-11-25 15:30:11.410623+00	\N	32
0x6dd6c111587b2124bbd315e451216dab566c609e	0xa6b2f6d6c03a21f62b6ebf41ad4dd0b7464861bf	77fc693461750f739b225c9745e8741139ea836b7ae9d8d3938b90edbef9006ceb8665b5373815e794387b4767d68d03288d166ad1f1e9c040e673d732ce88eb	0xc41360617d3c789036dd32c04d5460753283e749	2026-11-25 15:30:17.477537+00	\N	32
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	0x2d481c5cb134f362c39ee2034e754a1b801b6658	16a9c965eb9358f58a5944dd5267cb822de2318b102d46985d0a14b950c4e38162586253bed0b273f66249d617c3c0304f60dc0957e4a1776c76cf7c77cd0d20	0x9a344390b99a2cd511f5c06a0fee82cd6d3f78fb	2026-11-25 15:29:54.230366+00	\N	16
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	0x379aa0d55f82c299be13f3daacdc6dbb080a3e6e	b4038b4e2170f07fc9f09e09239d6ff55104bb3aa6891182bb746a410543505f19729590925cae92221c58e576c0d2193376fa23b7d64d67614b5d8cd588d951	0xed12b46c98a13e880b86febb414a07a6af0b2aa7	2026-11-25 15:29:28.658727+00	\N	33
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	0x45899aec1488da1831ea65a879f62e460631284d	422b169fb08dc88fd5206670de64207a33cbcdb3619486d3f9536c68f72a09945173fcfd107dd2966aeb5b9f6a8e2003b3e64e48bc857303db2f5c8f235266cf	0xfba1e9025455bbae83fab138af6b5d16287ee129	2026-11-25 15:29:36.562592+00	\N	33
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	0x558d023212b40072f18de63e27adace57541b746	afb47d76d2e2ec3226c49f27fb7dbe8390b6a7197cd31f059c8edce9b14af470a3d96a56a7ee3d943e40e517bf5d3ea4ffec90dbdc0a49cd61e5cfcfbd34b777	0x62242ea66c1c57d35ae09e588f0a564795015208	2026-11-25 15:29:46.91301+00	\N	33
\.


--
-- Data for Name: alerts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.alerts (id, episode_id, type, owner, started_at, created_at, broad, rules_version) FROM stdin;
1	d0cb6552-1795620812	NODE_DOWN	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:33:32.192693+00	2026-11-25 15:44:32.192851+00	f	watch-rules-v1
2	cc7185d2-1795620932	AGENT_SILENT	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:35:32.192642+00	2026-11-25 15:46:32.192631+00	f	watch-rules-v1
3	cc7185d2-1795620932	RECOVERED	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:35:32.192642+00	2026-11-25 15:54:14.614169+00	f	watch-rules-v1
4	d0cb6552-1795620812	RECOVERED	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:33:32.192693+00	2026-11-25 15:54:14.614169+00	f	watch-rules-v1
\.


--
-- Data for Name: audit_log; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.audit_log (id, at, actor, action, detail, prev_hash, hash) FROM stdin;
1	2026-11-25 15:29:28.658727+00	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	register_agent	agent 0xed12b46c98a13e880b86febb414a07a6af0b2aa7		2a2fc8682d990d2c1057f6d3bfe1ed7d8a426f957fa94a9ccb60f06e6526e581
2	2026-11-25 15:31:52.326485+00	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	set_manager	from 0x to 0xf8a1…3577	2a2fc8682d990d2c1057f6d3bfe1ed7d8a426f957fa94a9ccb60f06e6526e581	94443e8a92a66bcfaac191198d747345ebadf0e2fc5a0889c49003019b3abc94
3	2026-11-25 15:32:00.908282+00	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	set_manager	from 0xf8a1…3577 to 0xf8a1…3577	94443e8a92a66bcfaac191198d747345ebadf0e2fc5a0889c49003019b3abc94	094687cb6b3ae9e53192e880d3fd18b3881528b8edd011153eaf8a09909e0d4e
4	2026-11-25 16:01:42.246412+00	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	read_contacts	7 validators	094687cb6b3ae9e53192e880d3fd18b3881528b8edd011153eaf8a09909e0d4e	e13a5fad2c0b8ad9b0421c68594fc6306c2a524894a7bdb086a999a0b2070efd
5	2026-11-25 16:02:03.684629+00	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	read_contacts	7 validators	e13a5fad2c0b8ad9b0421c68594fc6306c2a524894a7bdb086a999a0b2070efd	6439c5dad253f4082ccbb8b98b92a74873229dfe468d8c2f19015e2974e75bf7
\.


--
-- Data for Name: check_results; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.check_results (owner, at, state, code, signals, rules_version) FROM stdin;
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:23:32.192136+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:24:32.193159+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:25:32.192187+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:26:32.195987+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:27:32.192798+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:28:32.191951+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:28:32.191951+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:28:32.191951+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:28:32.191951+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:28:32.191951+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:28:32.191951+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:28:32.191951+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:29:32.192387+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:29:32.192387+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:29:32.192387+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:29:32.192387+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:29:32.192387+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:29:32.192387+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:29:32.192387+00	UNKNOWN	NOT_REGISTERED	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:30:32.192101+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 10}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:30:32.192101+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:30:32.192101+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:30:32.192101+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 30}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:30:32.192101+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 17}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:30:32.192101+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 22}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:30:32.192101+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 25}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:31:32.192215+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 10}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:31:32.192215+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:31:32.192215+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:31:32.192215+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:31:32.192215+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 17}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:31:32.192215+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 22}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:31:32.192215+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 25}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:32:32.19241+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:32:32.19241+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:32:32.19241+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:32:32.19241+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 25}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:32:32.19241+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:32:32.19241+00	UNKNOWN	P2P_UNSEEN	{"s1": true, "s2": true, "s3": {"mon": false}, "lag": 17}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:32:32.19241+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 20}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:33:32.192693+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:33:32.192693+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:33:32.192693+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 2}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:33:32.192693+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:33:32.192693+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 27}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:33:32.192693+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 325}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:33:32.192693+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 14}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:34:32.192691+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:34:32.192691+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:34:32.192691+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 3}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:34:32.192691+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:34:32.192691+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 43}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:34:32.192691+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 341}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:34:32.192691+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:35:32.192642+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:35:32.192642+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:35:32.192642+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:35:32.192642+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 18}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:35:32.192642+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:35:32.192642+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 359}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:35:32.192642+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 14}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:36:32.192192+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:36:32.192192+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:36:32.192192+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:36:32.192192+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:36:32.192192+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:36:32.192192+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 375}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:36:32.192192+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:37:32.192318+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:37:32.192318+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:37:32.192318+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 2}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:37:32.192318+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:37:32.192318+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:37:32.192318+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 390}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:37:32.192318+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:38:32.192062+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:38:32.192062+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:38:32.192062+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:38:32.192062+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 17}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:38:32.192062+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:38:32.192062+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 407}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:38:32.192062+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:39:32.192226+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:39:32.192226+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:39:32.192226+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:39:32.192226+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 18}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:39:32.192226+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:39:32.192226+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 425}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:39:32.192226+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:40:32.19196+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:40:32.19196+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:40:32.19196+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 3}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:40:32.19196+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:40:32.19196+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:40:32.19196+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 440}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:40:32.19196+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:42:32.192679+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:42:32.192679+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:42:32.192679+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:42:32.192679+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 18}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:42:32.192679+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:42:32.192679+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 473}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:42:32.192679+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:41:32.192199+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:41:32.192199+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:41:32.192199+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 2}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:41:32.192199+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:41:32.192199+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:41:32.192199+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 455}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:41:32.192199+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:43:32.192184+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:43:32.192184+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:43:32.192184+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:43:32.192184+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 17}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:43:32.192184+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:43:32.192184+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 490}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:43:32.192184+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:44:32.192851+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 5}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:44:32.192851+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 8}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:44:32.192851+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 2}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:44:32.192851+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:44:32.192851+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:44:32.192851+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 505}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:44:32.192851+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 14}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:45:32.191963+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:45:32.191963+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:45:32.191963+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 3}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:45:32.191963+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:45:32.191963+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:45:32.191963+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 521}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:45:32.191963+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 12}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:46:32.192631+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:46:32.192631+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 7}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:46:32.192631+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:46:32.192631+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 18}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:46:32.192631+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:46:32.192631+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 539}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:46:32.192631+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 14}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:48:14.61454+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:48:14.61454+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 3}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:48:14.61454+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 15}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:48:14.61454+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:48:14.61454+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:48:14.61454+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 566}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:48:14.61454+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 9}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:49:14.61422+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:49:14.61422+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:49:14.61422+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:49:14.61422+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:49:14.61422+00	AGENT_SILENT		{"s1": false, "s2": false, "s3": {"mon": true}}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:49:14.61422+00	NODE_DOWN		{"s1": true, "s2": false, "s3": {"mon": false}, "lag": 581}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:49:14.61422+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 6}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:51:14.614081+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:51:14.614081+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:51:14.614081+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 28}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:51:14.614081+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 21}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:51:14.614081+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:51:14.614081+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:51:14.614081+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:50:14.613712+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:50:14.613712+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:50:14.613712+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 18}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:50:14.613712+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 14}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:50:14.613712+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 14}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:50:14.613712+00	NODE_STUCK		{"s1": true, "s2": false, "s3": {"mon": true}, "lag": 601}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:50:14.613712+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 11}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:52:14.613513+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:52:14.613513+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:52:14.613513+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 28}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:52:14.613513+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 21}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:52:14.613513+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:52:14.613513+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:52:14.613513+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:53:14.613487+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:53:14.613487+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:53:14.613487+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 28}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:53:14.613487+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 21}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:53:14.613487+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:53:14.613487+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:53:14.613487+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:54:14.614169+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:54:14.614169+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:54:14.614169+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 28}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:54:14.614169+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 21}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:54:14.614169+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:54:14.614169+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:54:14.614169+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:55:14.613767+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:55:14.613767+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:55:14.613767+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:55:14.613767+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:55:14.613767+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:55:14.613767+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:55:14.613767+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:56:14.61406+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:56:14.61406+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:56:14.61406+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:56:14.61406+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:56:14.61406+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:56:14.61406+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:56:14.61406+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:57:14.614491+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:57:14.614491+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:57:14.614491+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:57:14.614491+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:57:14.614491+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:57:14.614491+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:57:14.614491+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:59:14.614125+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:59:14.614125+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:59:14.614125+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:59:14.614125+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:59:14.614125+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:59:14.614125+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:59:14.614125+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:01:14.614324+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 1}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:01:14.614324+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 4}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:01:14.614324+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 28}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:01:14.614324+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 21}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:01:14.614324+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 24}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:01:14.614324+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 13}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:01:14.614324+00	UP		{"s1": true, "s2": true, "s3": {"mon": true}, "lag": 16}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:58:14.614347+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:58:14.614347+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:58:14.614347+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:58:14.614347+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:58:14.614347+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:58:14.614347+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:58:14.614347+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:00:14.6137+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:00:14.6137+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:00:14.6137+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:00:14.6137+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:00:14.6137+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:00:14.6137+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:00:14.6137+00	UNKNOWN	MONITOR_UNHEALTHY	{"s1": false, "s2": false}	watch-rules-v1
\.


--
-- Data for Name: contacts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.contacts (owner, channel, value, state, verified_at, fail_count, updated_at) FROM stdin;
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	telegram	xOB22amqIVX8kbYHd8y1am53+RgajVgH43B3c16eP+8=	verified	2026-11-25 15:31:19.925885+00	0	2026-11-25 15:31:19.925885+00
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	telegram	NNcmBNt4Z/lkJq+2j/6AlIdcfp0l4IDf3RWyZTO+7/8=	verified	2026-11-25 15:31:38.383927+00	0	2026-11-25 15:54:29.56625+00
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	telegram	QVcclFjBofQ4hMnaAi85NNjJ0g3s5cge0m8iArmAiFE=	verified	2026-11-25 15:31:32.769841+00	0	2026-11-25 15:54:29.569991+00
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	telegram	XkcbLobjeLfz04+EqDLtws2JJaz2WInQ1H1oyiulbb8=	verified	2026-11-25 15:31:26.14891+00	0	2026-11-25 15:54:29.572532+00
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	email	fO/2AMdcQL2Gq/Jtmo/rCwtllX58pdOIUMpkY2JE/t5mwXirCB8JbSvoexM=	verified	2026-11-25 15:31:43.964189+00	0	2026-11-25 15:54:29.575655+00
\.


--
-- Data for Name: cursors; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cursors (key, value) FROM stdin;
poll_offset_telegram	104
registry_scan_block	662
notifier_alert_id	4
notifier_undeliverable_alert_id	2
\.


--
-- Data for Name: deliveries; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.deliveries (id, alert_id, episode_id, kind, recipient, role, channel, state, attempts, next_at, last_error, body, created_at, sent_at) FROM stdin;
2	1	d0cb6552-1795620812	alert	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	owner	telegram	sent	1	2026-11-25 15:44:46.858146+00		🔴 نود ولیدیتور از ۱۱ دقیقه پیش در دسترس نیست\nولیدیتور: 0xd0cb…1dd2   وضعیت: NODE_DOWN\nآخرین ضربان: ۱۹:۱۳\nآپ‌تایم ۲۴ ساعت: ۱۴٫۳٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 15:44:46.858146+00	2026-11-25 15:44:46.863345+00
3	1	d0cb6552-1795620812	alert	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	manager	telegram	sent	1	2026-11-25 15:44:46.859335+00		🔴 نود ولیدیتور از ۱۱ دقیقه پیش در دسترس نیست\nولیدیتور: 0xd0cb…1dd2   وضعیت: NODE_DOWN\nآخرین ضربان: ۱۹:۱۳\nآپ‌تایم ۲۴ ساعت: ۱۴٫۳٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 15:44:46.859335+00	2026-11-25 15:44:46.872428+00
1	1	d0cb6552-1795620812	alert	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	owner	email	sent	1	2026-11-25 15:44:46.856467+00		🔴 نود ولیدیتور از ۱۱ دقیقه پیش در دسترس نیست\nولیدیتور: 0xd0cb…1dd2   وضعیت: NODE_DOWN\nآخرین ضربان: ۱۹:۱۳\nآپ‌تایم ۲۴ ساعت: ۱۴٫۳٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 15:44:46.856467+00	2026-11-25 15:44:46.878017+00
4	2	cc7185d2-1795620932	alert	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	owner	telegram	sent	1	2026-11-25 15:46:46.853791+00		🟡 ایجنت ولیدیتور ۱۱ دقیقه است ضربان نمی‌فرستد (نود در شبکه دیده می‌شود)\nولیدیتور: 0xcc71…28d0   وضعیت: AGENT_SILENT\nآخرین ضربان: ۱۹:۰۱   آخرین ارتفاع دیده‌شده: ۲۹۸\nآپ‌تایم ۲۴ ساعت: ۱۰۰٫۰٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 15:46:46.853791+00	2026-11-25 15:46:46.857637+00
5	3	cc7185d2-1795620932	alert	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	owner	telegram	sent	1	2026-11-25 15:54:29.561383+00		🟢 نود ولیدیتور دوباره سالم است (مدت اختلال: ۱۹ دقیقه)\nولیدیتور: 0xcc71…28d0   وضعیت: UP\nآخرین ضربان: ۱۹:۲۴   آخرین ارتفاع دیده‌شده: ۷۲۷\nآپ‌تایم ۲۴ ساعت: ۱۰۰٫۰٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 15:54:29.561383+00	2026-11-25 15:54:29.56625+00
7	4	d0cb6552-1795620812	alert	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	owner	telegram	sent	1	2026-11-25 15:54:29.563723+00		🟢 نود ولیدیتور دوباره سالم است (مدت اختلال: ۲۱ دقیقه)\nولیدیتور: 0xd0cb…1dd2   وضعیت: UP\nآخرین ضربان: ۱۹:۲۳   آخرین ارتفاع دیده‌شده: ۷۰۸\nآپ‌تایم ۲۴ ساعت: ۲۵٫۳٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 15:54:29.563723+00	2026-11-25 15:54:29.569991+00
8	4	d0cb6552-1795620812	alert	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	manager	telegram	sent	1	2026-11-25 15:54:29.564546+00		🟢 نود ولیدیتور دوباره سالم است (مدت اختلال: ۲۱ دقیقه)\nولیدیتور: 0xd0cb…1dd2   وضعیت: UP\nآخرین ضربان: ۱۹:۲۳   آخرین ارتفاع دیده‌شده: ۷۰۸\nآپ‌تایم ۲۴ ساعت: ۲۵٫۳٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 15:54:29.564546+00	2026-11-25 15:54:29.572532+00
6	4	d0cb6552-1795620812	alert	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	owner	email	sent	1	2026-11-25 15:54:29.563466+00		🟢 نود ولیدیتور دوباره سالم است (مدت اختلال: ۲۱ دقیقه)\nولیدیتور: 0xd0cb…1dd2   وضعیت: UP\nآخرین ضربان: ۱۹:۲۳   آخرین ارتفاع دیده‌شده: ۷۰۸\nآپ‌تایم ۲۴ ساعت: ۲۵٫۳٪\nجزئیات: http://surwatch-live-fakes:8080	2026-11-25 15:54:29.563466+00	2026-11-25 15:54:29.575655+00
\.


--
-- Data for Name: engine_state; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.engine_state (owner, payload) FROM stdin;
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	{"Code": "", "Sent": null, "Owner": "0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2", "Since": "2026-11-25T16:01:14.614324177Z", "State": "UP", "UpSince": "2026-11-25T16:01:14.614324177Z", "LastTick": "2026-11-25T16:01:14.614324177Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	{"Code": "", "Sent": null, "Owner": "0xf8a13c5a99e617cb22eb184d14266de4b82d3577", "Since": "2026-11-25T16:01:14.614324177Z", "State": "UP", "UpSince": "2026-11-25T16:01:14.614324177Z", "LastTick": "2026-11-25T16:01:14.614324177Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	{"Code": "", "Sent": null, "Owner": "0x10e3f7133f3fc58a30b17ae57846278dbab4044f", "Since": "2026-11-25T16:01:14.614324177Z", "State": "UP", "UpSince": "2026-11-25T16:01:14.614324177Z", "LastTick": "2026-11-25T16:01:14.614324177Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	{"Code": "", "Sent": null, "Owner": "0x3481a641697c8706d924ede2fa2ed7fd40b25e9c", "Since": "2026-11-25T16:01:14.614324177Z", "State": "UP", "UpSince": "2026-11-25T16:01:14.614324177Z", "LastTick": "2026-11-25T16:01:14.614324177Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0x6dd6c111587b2124bbd315e451216dab566c609e	{"Code": "", "Sent": null, "Owner": "0x6dd6c111587b2124bbd315e451216dab566c609e", "Since": "2026-11-25T16:01:14.614324177Z", "State": "UP", "UpSince": "2026-11-25T16:01:14.614324177Z", "LastTick": "2026-11-25T16:01:14.614324177Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	{"Code": "", "Sent": null, "Owner": "0xb0b3fff6193b77c818f3b7733e1966d60cf8239e", "Since": "2026-11-25T16:01:14.614324177Z", "State": "UP", "UpSince": "2026-11-25T16:01:14.614324177Z", "LastTick": "2026-11-25T16:01:14.614324177Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	{"Code": "", "Sent": null, "Owner": "0xcc7185d2082e647e2d3643596d626ab2f8f028d0", "Since": "2026-11-25T16:01:14.614324177Z", "State": "UP", "UpSince": "2026-11-25T16:01:14.614324177Z", "LastTick": "2026-11-25T16:01:14.614324177Z", "EpisodeAt": "0001-01-01T00:00:00Z", "EpisodeID": ""}
\.


--
-- Data for Name: heartbeats_latest; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.heartbeats_latest (owner, recv_at, head_changed_at, payload) FROM stdin;
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:01:27.129943+00	2026-11-25 16:01:27.129943+00	{"v": 1, "ts": 1795622487, "seq": 16, "owner": "0xcc7185d2082e647e2d3643596d626ab2f8f028d0", "peers": 7, "nodeId": "16a9c965eb9358f58a5944dd5267cb822de2318b102d46985d0a14b950c4e38162586253bed0b273f66249d617c3c0304f60dc0957e4a1776c76cf7c77cd0d20", "rpc_ok": true, "rtt_ms": 0, "chainId": 262025, "cpu_pct": 23, "mem_pct": 40, "syncing": false, "operator": "0x2d481c5cb134f362c39ee2034e754a1b801b6658", "head_hash": "0xe53e9acbdc912ebaca5a203c4da18b9e4b6cbc8f16ca2f39df3e808ef6e7daad", "load_x100": 151, "head_number": 937, "agentVersion": "0.1.0", "disk_free_pct": 84, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 143}
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:01:13.760203+00	2026-11-25 16:01:13.760203+00	{"v": 1, "ts": 1795622473, "seq": 32, "owner": "0x10e3f7133f3fc58a30b17ae57846278dbab4044f", "peers": 7, "nodeId": "2ee39b7b2596c0c76fb2ea87086e4c58a289cfd0289c916db47eaec04e1f4c8db14f441259e9be70e44b0ce2e24ba2f808884be2b0d700384f655b5460062614", "rpc_ok": true, "rtt_ms": 1, "chainId": 262025, "cpu_pct": 26, "mem_pct": 40, "syncing": false, "operator": "0x5bacebcfdad4d946b184276309a0b8b0a28ab608", "head_hash": "0xae40f85c5ed1da2fe06e200ea4ada631f3eac6b04ae91bb5a4e99144b5eb919a", "load_x100": 136, "head_number": 930, "agentVersion": "0.1.0", "disk_free_pct": 84, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 785}
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:01:42.731299+00	2026-11-25 16:01:42.731299+00	{"v": 1, "ts": 1795622502, "seq": 33, "owner": "0xf8a13c5a99e617cb22eb184d14266de4b82d3577", "peers": 7, "nodeId": "422b169fb08dc88fd5206670de64207a33cbcdb3619486d3f9536c68f72a09945173fcfd107dd2966aeb5b9f6a8e2003b3e64e48bc857303db2f5c8f235266cf", "rpc_ok": true, "rtt_ms": 3, "chainId": 262025, "cpu_pct": 24, "mem_pct": 41, "syncing": false, "operator": "0x45899aec1488da1831ea65a879f62e460631284d", "head_hash": "0x1229a543449b89982a2831145fe17ff853760bd239b573b7bc2e2beb4052e977", "load_x100": 176, "head_number": 945, "agentVersion": "0.1.0", "disk_free_pct": 84, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 640}
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:01:07.842068+00	2026-11-25 16:01:07.842068+00	{"v": 1, "ts": 1795622467, "seq": 32, "owner": "0x3481a641697c8706d924ede2fa2ed7fd40b25e9c", "peers": 7, "nodeId": "6a63fd39eae71f791ca03ddf0ff7c7f675177b28cc80f0fd0ba8ec30a122bfc070f161fb297305f4ae9685d47fec8133e49af6747866651a26d4977a6c8fd29d", "rpc_ok": true, "rtt_ms": 1, "chainId": 262025, "cpu_pct": 28, "mem_pct": 40, "syncing": false, "operator": "0xf7ab920c3c19d225a9f6c2ee05599150f4d128f6", "head_hash": "0xe49179bec5635b0a6c3a888a29653ec46cbf23319d41020a40433e29704775da", "load_x100": 140, "head_number": 927, "agentVersion": "0.1.0", "disk_free_pct": 84, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 854}
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:01:19.98831+00	2026-11-25 16:01:19.98831+00	{"v": 1, "ts": 1795622479, "seq": 32, "owner": "0x6dd6c111587b2124bbd315e451216dab566c609e", "peers": 7, "nodeId": "77fc693461750f739b225c9745e8741139ea836b7ae9d8d3938b90edbef9006ceb8665b5373815e794387b4767d68d03288d166ad1f1e9c040e673d732ce88eb", "rpc_ok": true, "rtt_ms": 1, "chainId": 262025, "cpu_pct": 25, "mem_pct": 41, "syncing": false, "operator": "0xa6b2f6d6c03a21f62b6ebf41ad4dd0b7464861bf", "head_hash": "0x09c79938c382c8baa8ce69fad56ba016928b5bd8448afabf565177603ba9e275", "load_x100": 142, "head_number": 933, "agentVersion": "0.1.0", "disk_free_pct": 84, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 986}
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:01:32.28499+00	2026-11-25 16:01:32.28499+00	{"v": 1, "ts": 1795622492, "seq": 33, "owner": "0xb0b3fff6193b77c818f3b7733e1966d60cf8239e", "peers": 7, "nodeId": "b4038b4e2170f07fc9f09e09239d6ff55104bb3aa6891182bb746a410543505f19729590925cae92221c58e576c0d2193376fa23b7d64d67614b5d8cd588d951", "rpc_ok": true, "rtt_ms": 2, "chainId": 262025, "cpu_pct": 23, "mem_pct": 40, "syncing": false, "operator": "0x379aa0d55f82c299be13f3daacdc6dbb080a3e6e", "head_hash": "0x7b8ee5b9f973aec069c3ba121f51633a017a73e55cc578880f5e9bd6ba2b4069", "load_x100": 163, "head_number": 940, "agentVersion": "0.1.0", "disk_free_pct": 84, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 256}
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:01:49.151018+00	2026-11-25 16:01:49.151018+00	{"v": 1, "ts": 1795622509, "seq": 33, "owner": "0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2", "peers": 7, "nodeId": "afb47d76d2e2ec3226c49f27fb7dbe8390b6a7197cd31f059c8edce9b14af470a3d96a56a7ee3d943e40e517bf5d3ea4ffec90dbdc0a49cd61e5cfcfbd34b777", "rpc_ok": true, "rtt_ms": 1, "chainId": 262025, "cpu_pct": 24, "mem_pct": 41, "syncing": false, "operator": "0x558d023212b40072f18de63e27adace57541b746", "head_hash": "0x32b89c102e27b658edb1d05aff761f60366a70cc4cd72d4e46fd0cad197a7531", "load_x100": 178, "head_number": 948, "agentVersion": "0.1.0", "disk_free_pct": 84, "client_version": "besu/v26.9.0/linux-x86_64/openjdk-java-25", "clock_offset_ms": 605}
\.


--
-- Data for Name: link_codes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.link_codes (code_hash, owner, channel, value, expires_at, used_at) FROM stdin;
907d32046f04b3e15d78abfd9daa4e2bf27c05ca28ab668f18ba851cf803c458	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	telegram		2026-11-25 15:41:19.74386+00	2026-11-25 15:31:19.92505+00
ae0cd990a85543f372c64d7ed5de5ff8b61085747d93071e5c7033e055301192	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	telegram		2026-11-25 15:41:26.076262+00	2026-11-25 15:31:26.1485+00
6ee462b34c9116234c15397a3420b00524d4d06c3547f07d8409bc2f1b1ef7ff	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	telegram		2026-11-25 15:41:32.579761+00	2026-11-25 15:31:32.768941+00
3e4e38e63b5e58784d9b3ed46bf8931833a6473d208cddb59d549bad2e07b3cd	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	telegram		2026-11-25 15:41:38.290272+00	2026-11-25 15:31:38.383579+00
b25c6dd318504bf8be159d5751a444da6dc86866829902c1b539f339ae4cc2f7	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	email	fO/2AMdcQL2Gq/Jtmo/rCwtllX58pdOIUMpkY2JE/t5mwXirCB8JbSvoexM=	2026-11-25 15:41:43.954523+00	2026-11-25 15:31:43.963865+00
\.


--
-- Data for Name: maintenance_windows; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.maintenance_windows (id, owner, start_at, end_at) FROM stdin;
\.


--
-- Data for Name: settings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.settings (key, value) FROM stdin;
manager_address	0xf8a13c5a99e617cb22eb184d14266de4b82d3577
\.


--
-- Data for Name: state_log; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.state_log (id, owner, at, from_state, to_state, code, episode_id) FROM stdin;
1	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:23:32.192136+00		UNKNOWN	NOT_REGISTERED	
2	0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:28:32.191951+00		UNKNOWN	NOT_REGISTERED	
3	0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:28:32.191951+00		UNKNOWN	NOT_REGISTERED	
4	0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:28:32.191951+00		UNKNOWN	NOT_REGISTERED	
5	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:28:32.191951+00		UNKNOWN	NOT_REGISTERED	
6	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:28:32.191951+00		UNKNOWN	NOT_REGISTERED	
7	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:28:32.191951+00		UNKNOWN	NOT_REGISTERED	
8	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:29:32.192387+00	UNKNOWN	AGENT_SILENT		
9	0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:30:32.192101+00	UNKNOWN	UP		
10	0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:30:32.192101+00	UNKNOWN	UP		
11	0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:30:32.192101+00	UNKNOWN	UP		
12	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:30:32.192101+00	AGENT_SILENT	UP		
13	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:30:32.192101+00	UNKNOWN	UP		
14	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:30:32.192101+00	UNKNOWN	UP		
15	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:30:32.192101+00	UNKNOWN	UP		
16	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:32:32.19241+00	UP	UNKNOWN	P2P_UNSEEN	
17	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:33:32.192693+00	UNKNOWN	NODE_DOWN		
18	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:35:32.192642+00	UP	AGENT_SILENT		
19	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:50:14.613712+00	AGENT_SILENT	UP		cc7185d2-1795620932
20	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:50:14.613712+00	NODE_DOWN	NODE_STUCK		d0cb6552-1795620812
21	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:51:14.614081+00	NODE_STUCK	UP		d0cb6552-1795620812
22	0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:55:14.613767+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
23	0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:55:14.613767+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
24	0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:55:14.613767+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
25	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:55:14.613767+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
26	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:55:14.613767+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
27	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:55:14.613767+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
28	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:55:14.613767+00	UP	UNKNOWN	MONITOR_UNHEALTHY	
29	0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:01:14.614324+00	UNKNOWN	UP		
30	0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:01:14.614324+00	UNKNOWN	UP		
31	0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:01:14.614324+00	UNKNOWN	UP		
32	0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:01:14.614324+00	UNKNOWN	UP		
33	0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:01:14.614324+00	UNKNOWN	UP		
34	0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:01:14.614324+00	UNKNOWN	UP		
35	0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:01:14.614324+00	UNKNOWN	UP		
\.


--
-- Data for Name: uptime_buckets; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.uptime_buckets (owner, bucket_start, up, agent_silent, down, stuck, maintenance, unknown) FROM stdin;
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:20:00+00	0	0	0	0	0	60.001022937
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:25:00+00	0	0	0	0	0	60.000436817
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:25:00+00	0	0	0	0	0	60.000436817
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:25:00+00	0	0	0	0	0	60.000436817
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:25:00+00	0	60.000436817	0	0	0	239.99879179500002
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:25:00+00	0	0	0	0	0	60.000436817
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:25:00+00	0	0	0	0	0	60.000436817
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:25:00+00	0	0	0	0	0	60.000436817
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:45:00+00	0	0	282.421368518	0	0	0
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:45:00+00	282.421368518	0	0	0	0	0
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:50:00+00	299.999949315	0	0	0	0	0
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:50:00+00	299.999949315	0	0	0	0	0
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:50:00+00	299.999949315	0	0	0	0	0
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:35:00+00	299.99953434099996	0	0	0	0	0
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:35:00+00	299.99953434099996	0	0	0	0	0
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:35:00+00	299.99953434099996	0	0	0	0	0
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:35:00+00	299.99953434099996	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:35:00+00	0	299.99953434099996	0	0	0	0
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:30:00+00	300.000303736	0	0	0	0	0
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:30:00+00	300.000303736	0	0	0	0	0
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:30:00+00	300.000303736	0	0	0	0	0
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:30:00+00	300.000303736	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:30:00+00	300.000303736	0	0	0	0	0
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:30:00+00	119.99982717399999	0	120.000281262	0	0	60.0001953
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:30:00+00	300.000303736	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:50:00+00	299.999949315	0	0	0	0	0
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:40:00+00	300.000625798	0	0	0	0	0
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:35:00+00	0	0	299.99953434099996	0	0	0
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:35:00+00	299.99953434099996	0	0	0	0	0
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:50:00+00	240.00045739499998	0	0	59.99949192	0	0
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:40:00+00	300.000625798	0	0	0	0	0
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:40:00+00	300.000625798	0	0	0	0	0
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:40:00+00	300.000625798	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:40:00+00	0	300.000625798	0	0	0	0
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:40:00+00	0	0	300.000625798	0	0	0
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:40:00+00	300.000625798	0	0	0	0	0
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:45:00+00	282.421368518	0	0	0	0	0
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:45:00+00	282.421368518	0	0	0	0	0
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:45:00+00	282.421368518	0	0	0	0	0
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:45:00+00	282.421368518	0	0	0	0	0
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:45:00+00	0	282.421368518	0	0	0	0
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:50:00+00	299.999949315	0	0	0	0	0
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 16:00:00+00	60.00062358	0	0	0	0	59.999575065
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:55:00+00	0	0	0	0	0	299.999955862
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 15:55:00+00	0	0	0	0	0	299.999955862
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 15:55:00+00	0	0	0	0	0	299.999955862
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 15:55:00+00	0	0	0	0	0	299.999955862
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 15:55:00+00	0	0	0	0	0	299.999955862
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	2026-11-25 15:50:00+00	299.999949315	0	0	0	0	0
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	2026-11-25 16:00:00+00	60.00062358	0	0	0	0	59.999575065
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 16:00:00+00	60.00062358	0	0	0	0	59.999575065
0x6dd6c111587b2124bbd315e451216dab566c609e	2026-11-25 15:55:00+00	0	0	0	0	0	299.999955862
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 15:55:00+00	0	0	0	0	0	299.999955862
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	2026-11-25 16:00:00+00	60.00062358	0	0	0	0	59.999575065
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	2026-11-25 16:00:00+00	60.00062358	0	0	0	0	59.999575065
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	2026-11-25 16:00:00+00	60.00062358	0	0	0	0	59.999575065
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	2026-11-25 16:00:00+00	60.00062358	0	0	0	0	59.999575065
\.


--
-- Data for Name: validators_cache; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.validators_cache (owner, operator, status, updated_at) FROM stdin;
0xd0cb65529cd8d0907c53e6ae4d444a2c6c4c1dd2	0x558d023212b40072f18de63e27adace57541b746	2	2026-11-25 15:52:14.658548+00
0xf8a13c5a99e617cb22eb184d14266de4b82d3577	0x45899aec1488da1831ea65a879f62e460631284d	2	2026-11-25 15:52:14.658548+00
0x10e3f7133f3fc58a30b17ae57846278dbab4044f	0x5bacebcfdad4d946b184276309a0b8b0a28ab608	2	2026-11-25 15:52:14.658548+00
0x3481a641697c8706d924ede2fa2ed7fd40b25e9c	0xf7ab920c3c19d225a9f6c2ee05599150f4d128f6	2	2026-11-25 15:52:14.658548+00
0x6dd6c111587b2124bbd315e451216dab566c609e	0xa6b2f6d6c03a21f62b6ebf41ad4dd0b7464861bf	2	2026-11-25 15:52:14.658548+00
0xb0b3fff6193b77c818f3b7733e1966d60cf8239e	0x379aa0d55f82c299be13f3daacdc6dbb080a3e6e	2	2026-11-25 15:52:14.658548+00
0xcc7185d2082e647e2d3643596d626ab2f8f028d0	0x2d481c5cb134f362c39ee2034e754a1b801b6658	2	2026-11-25 15:52:14.658548+00
\.


--
-- Name: alerts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.alerts_id_seq', 4, true);


--
-- Name: audit_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.audit_log_id_seq', 5, true);


--
-- Name: deliveries_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.deliveries_id_seq', 8, true);


--
-- Name: maintenance_windows_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.maintenance_windows_id_seq', 1, false);


--
-- Name: state_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.state_log_id_seq', 35, true);


--
-- PostgreSQL database dump complete
--

\unrestrict FxXgwbtjXQefgGLt6MCc2VssPuOUD7hciNU1IIaXXZMUu2gUfOTYxwOWZ7vWbJT

