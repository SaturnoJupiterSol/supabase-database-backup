
\restrict Ot7AC5RqCSbotST9l6L31rKQldCBC6hzPo6GerKG0MpmDfPSOybkTJICiwgapb9

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

ALTER ROLE "anon" SET "statement_timeout" TO '3s';

ALTER ROLE "authenticated" SET "statement_timeout" TO '8s';

ALTER ROLE "authenticator" SET "statement_timeout" TO '8s';

\unrestrict Ot7AC5RqCSbotST9l6L31rKQldCBC6hzPo6GerKG0MpmDfPSOybkTJICiwgapb9

RESET ALL;
