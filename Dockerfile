ARG PHP_VER 7.4
FROM php:8.1-fpm-alpine

# Install packages and remove default server definition
RUN apk --no-cache add  \
	nginx \
	supervisor \
	curl \
	git \
	patch
	# patch && \
    # rm /etc/nginx/conf.d/default.conf
# install the PHP extensions we need
# postgresql-dev is needed for https://bugs.alpinelinux.org/issues/3642
RUN set -eux; \
	\
	apk add --no-cache --virtual .build-deps \
		coreutils \
		freetype-dev \
		libjpeg-turbo-dev \
		libpng-dev \
		libzip-dev \
		postgresql-dev \
	; \
	\
	docker-php-ext-configure gd \
		--with-freetype \
		--with-jpeg=/usr/include \
	; \
	\
	docker-php-ext-install -j "$(nproc)" \
		gd \
		opcache \
		pdo_mysql \
		pdo_pgsql \
		zip \
    bcmath \
	; \
	\
	runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
	apk add --virtual .drupal-phpexts-rundeps $runDeps; \
	apk del .build-deps

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=60'; \
		echo 'opcache.fast_shutdown=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini


# RUN apk add --no-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/community/ --allow-untrusted gnu-libiconv
# ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so php

# https://github.com/drupal/drupal/blob/9.0.1/composer.lock#L4052-L4053
# COPY --from=composer:1.10 /usr/bin/composer /usr/local/bin/
COPY --from=composer /usr/bin/composer /usr/local/bin/


# Configure nginx
COPY config/nginx.conf /etc/nginx/nginx.conf

# Configure PHP-FPM
# COPY config/fpm-pool.conf /etc/php7/php-fpm.d/www.conf
# COPY config/php.ini /etc/php7/conf.d/custom.ini

# Configure supervisord
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf


WORKDIR /var/www/html

RUN mkdir /.composer
RUN mkdir /.drush

# Make sure files/folders needed by the processes are accessable when they run under the nobody user
RUN chown -R nobody.nobody /var/www/html && \
  chown -R nobody.nobody /run && \
  chown -R nobody.nobody /var/lib/nginx && \
  chown -R nobody.nobody /.composer && \
  chown -R nobody.nobody /.drush && \
  chown -R nobody.nobody /var/log/nginx
# RUN  pecl install uploadprogress/


# Switch to use a non-root user from here on
USER nobody



# RUN composer global require hirak/prestissimo
RUN composer clear-cache
RUN COMPOSER_MEMORY_LIMIT=-1 composer create-project drupal/recommended-project:^9.5 ./ --no-interaction --no-cache
# RUN COMPOSER_MEMORY_LIMIT=-1 composer create-project srijanone/ezcontent-project:^2-dev ./ --stability dev --no-interaction
# RUN composer require 'drupal/layout_builder_reorder'
# RUN COMPOSER_MEMORY_LIMIT=-1 composer create-project drupalcommerce/project-base ./ --stability dev --no-interaction
# RUN COMPOSER_MEMORY_LIMIT=-1 composer create-project srijanone/ezdevportal-project ./web --no-interaction --no-cache
# RUN COMPOSER_MEMORY_LIMIT=-1 composer create-project drupal/recommended-project:^9.5 ./ --no-interaction --no-cache && \
# composer config --no-plugins allow-plugins.simplesamlphp/composer-module-installer true && \
# 		composer require 'drupal/simplesamlphp_auth:^3.3' && \
# 		composer config --no-plugins allow-plugins.simplesamlphp/composer-module-installer false
		# composer require drush/drush && \
		# composer require 'drupal/simplesamlphp_auth:^3.3'
# RUN printf "<php?\n\$settings.php['gigya_encryption_key']='56410fb46dae792dd32d6aca5a4bc47d58a56be0de4c73640573931c526fdc7211e0908cfa80a4a1e3ad56bb732e1691168be1f5f04aa2b61f4db17b5723352d';" >> ./web/sites/default/settings.local.php
# RUN COMPOSER_MEMORY_LIMIT=-1 composer create-project --no-interaction acquia/drupal-recommended-project ./ --no-interaction --no-cache && \
#   composer require acquia/blt

# Expose the port nginx is reachable on
EXPOSE 8080

ENV PATH=${PATH}:/var/www/html/vendor/bin:/usr/local/bin

COPY config/robots.txt /var/www/html/web/robots.txt
# Let supervisord start nginx & php-fpm
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

# Configure a healthcheck to validate that everything is up&running
#HEALTHCHECK --timeout=10s CMD curl --silent --fail http://127.0.0.1:9000/fpm-ping
