
\restrict 3ebPEtdwzYbvAeb4eEJpS5bRRFVIgfeBO97P4AOWTYzCVH02PWGxBk4YuqkEMs9

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

ALTER ROLE "anon" SET "statement_timeout" TO '3s';

ALTER ROLE "authenticated" SET "statement_timeout" TO '8s';

ALTER ROLE "authenticator" SET "statement_timeout" TO '8s';

\unrestrict 3ebPEtdwzYbvAeb4eEJpS5bRRFVIgfeBO97P4AOWTYzCVH02PWGxBk4YuqkEMs9

RESET ALL;
