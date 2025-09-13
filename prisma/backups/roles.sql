
\restrict eWrji6e8DnkLq6W51IUh3VIjyT26QUMUP3sBNldSaTXIjOt6eG1hVjHaX04omkd

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

ALTER ROLE "anon" SET "statement_timeout" TO '3s';

ALTER ROLE "authenticated" SET "statement_timeout" TO '8s';

ALTER ROLE "authenticator" SET "statement_timeout" TO '8s';

\unrestrict eWrji6e8DnkLq6W51IUh3VIjyT26QUMUP3sBNldSaTXIjOt6eG1hVjHaX04omkd

RESET ALL;
