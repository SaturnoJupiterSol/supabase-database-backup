
\restrict HQ1xily0m5ofTAuHBJaczE1Wtfk45vw6ai6fZXm6vYpkL5uykwpL57H5EBsOMcZ

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

ALTER ROLE "anon" SET "statement_timeout" TO '3s';

ALTER ROLE "authenticated" SET "statement_timeout" TO '8s';

ALTER ROLE "authenticator" SET "statement_timeout" TO '8s';

\unrestrict HQ1xily0m5ofTAuHBJaczE1Wtfk45vw6ai6fZXm6vYpkL5uykwpL57H5EBsOMcZ

RESET ALL;
