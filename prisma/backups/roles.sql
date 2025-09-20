
\restrict v8XVHTt1hzAfQ3UZVP5QZGoBHcnhX6j88qu9QZLHRCX91RPXzOpCWyX29d6AcCV

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

ALTER ROLE "anon" SET "statement_timeout" TO '3s';

ALTER ROLE "authenticated" SET "statement_timeout" TO '8s';

ALTER ROLE "authenticator" SET "statement_timeout" TO '8s';

\unrestrict v8XVHTt1hzAfQ3UZVP5QZGoBHcnhX6j88qu9QZLHRCX91RPXzOpCWyX29d6AcCV

RESET ALL;
