FROM debian:stable-slim AS sqitch-build
MAINTAINER David E. Wheeler <david@justatheory.com>
ENV BUILDROOT /work
ENV VERSION=0.9998

WORKDIR /$BUILDROOT
WORKDIR $BUILDROOT
COPY App-Sqitch-$VERSION.tar.gz .

# Install system dependencies.
RUN mkdir -p /usr/share/man/man1 /usr/share/man/man7 \
    && apt-get -qq update \
    && apt-get -qq install build-essential perl curl \
       unixodbc-dev firebird-dev sqlite libpq-dev libmariadbclient-dev \
    # && curl -LO https://cpan.metacpan.org/authors/id/D/DW/DWHEELER/App-Sqitch-$VERSION.tar.gz . \
    && mkdir src \
    && tar -zxf App-Sqitch-$VERSION.tar.gz --strip-components 1 -C src

# Install cpan and build dependencies.
ENV PERL5LIB $BUILDROOT/local/lib/perl5
RUN curl -sL --compressed https://git.io/cpm > cpm && chmod +x cpm \
    && ./cpm install -L local --verbose --no-test ExtUtils::MakeMaker \
    && ./cpm install -L local --verbose --no-test --with-recommends \
        --with-configure --cpanfile src/dist/cpanfile

# Build, test, bundle.
WORKDIR $BUILDROOT/src
RUN perl Build.PL --quiet --install_base /app --etcdir /etc/sqitch \
    --config installman1dir= --config installsiteman1dir= --config installman3dir= --config installsiteman3dir= \
    --with sqlite --with postgres --with firebird --with odbc \
    && ./Build test && ./Build bundle \
    && find /app -name '*.pod' | grep -v sqitch | xargs rm -rf

################################################################################
# Copy to the final image without all the build stuff.
FROM debian:stable-slim AS sqitch

# Install runtime system dependencies and remove unnecesary files.
RUN mkdir -p /usr/share/man/man1 /usr/share/man/man7 \
    && apt-get -qq update \
    && apt-get -qq --no-install-recommends install less libperl5.24 nano \
       sqlite3 \
       firebird3.0-utils libfbclient2 \
       libpq5 postgresql-client \
       mariadb-client-core-10.1 libmariadbclient18 libdbd-mysql-perl \
    && apt-cache pkgnames | grep python | xargs apt-get purge -qq \
    && apt-cache pkgnames | grep libmagic | xargs apt-get purge -qq \
    && apt-get clean \
    && rm -rf /var/cache/apt/* /var/lib/apt/lists/* /usr/bin/mysql?* \
    && rm -rf /plibs /man /usr/share/man /usr/share/doc /usr/share/postgresql \
        /usr/share/nano /etc/nanorc \
    && find / -name '*.pod' | grep -v sqitch | xargs rm -rf \
    && find / -name '*.ph' -delete \
    && find / -name '*.h' -delete

# Copy the app and config from the build image.
COPY --from=sqitch-build /app .
COPY --from=sqitch-build /etc /etc/

# Set up environment, entrypoint, and default command.
ENV LESS=-R HOME=/home LC_ALL=C.UTF-8 LANG=C.UTF-8 EDITOR=nano
WORKDIR /repo
ENTRYPOINT ["/bin/sqitch"]
CMD ["help"]