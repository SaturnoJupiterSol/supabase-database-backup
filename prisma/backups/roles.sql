
\restrict ZFUOZOTEjOKnzku3w29BgU6Tza57lOJpc09cti52f77M6nahOpOck3xia65jQ7R

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

ALTER ROLE "anon" SET "statement_timeout" TO '3s';

ALTER ROLE "authenticated" SET "statement_timeout" TO '8s';

ALTER ROLE "authenticator" SET "statement_timeout" TO '8s';

\unrestrict ZFUOZOTEjOKnzku3w29BgU6Tza57lOJpc09cti52f77M6nahOpOck3xia65jQ7R

RESET ALL;
